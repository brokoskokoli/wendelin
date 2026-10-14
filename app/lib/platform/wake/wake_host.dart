import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import '../channels.dart';
import 'service_audio_input.dart';

export '../channels.dart' show wakeEngineChannelName;

/// What the wake word host needs from the device (replaced in tests).
abstract interface class WakeParts {
  /// Stage 1 for all learned voices; `null` if nothing is learned.
  Future<WakeWordEngine?> engine();

  /// Stage 2; loads Whisper when needed and frees it again.
  WakeVerifier verifier();

  /// Frees everything the parts hold (Whisper).
  Future<void> dispose();
}

/// Dart side of the wake word service (WP50, ADR 0013): runs in the
/// headless engine of `WakeWordService` (`wakeWordMain`). Connects the
/// microphone of the service ([ServiceAudioInput]) with the two-stage
/// detection ([WakeWordListener]); a confirmed wake word frees the
/// microphone and goes to Kotlin together with its pre-roll (`hit`), which
/// opens the assistant overlay.
///
/// The listener is paused for as long as any hold exists: the overlay
/// (`hit` until `overlayClosed`) and conflicts (`conflict`: call, other
/// recording). Diagnostics (`wake-cand`, `wake-verify`, `wake-pause`,
/// `wake-resume`, `wake-alive`) contain no audio and no text.
///
/// Calls from Kotlin: `run` (`{verify}`), `audio` (`{pcm}`), `audioError`
/// (`{message}`), `conflict` (`{reason}`, `null` = free), `overlayClosed`,
/// `shutdown`. Calls to Kotlin: `ready`, `startMic`, `stopMic`, `hit`
/// (`{pcm, kw, score}`) and `failed` (`{reason}`).
final class WakeHost {
  /// Creates the host.
  WakeHost({
    required this.parts,
    required this.audio,
    this.channel = const MethodChannel(wakeEngineChannelName),
    this.aliveEvery = const Duration(minutes: 5),
  });

  /// Engine and verifier.
  final WakeParts parts;

  /// The microphone (the service, or a WAV in device tests).
  final AudioInput audio;

  /// Channel to the service.
  final MethodChannel channel;

  /// Interval of the `wake-alive` line.
  final Duration aliveEvery;

  WakeWordListener? _listener;
  bool _verify = true;
  final _holds = <String>{};
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _alive;
  Future<void> _ops = Future.value();
  bool _ending = false;

  /// Listens to the service and reports `ready`.
  Future<void> attach() async {
    channel.setMethodCallHandler(_onCall);
    await channel.invokeMethod<void>('ready');
  }

  Future<Object?> _onCall(MethodCall call) async {
    final args = call.arguments is Map
        ? call.arguments as Map<Object?, Object?>
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'run':
        await _serial(() => _run(verify: args['verify'] != false));
      case 'audio':
        final pcm = args['pcm'];
        if (audio case final ServiceAudioInput input when pcm is Uint8List) {
          input.push(pcm);
        }
      case 'audioError':
        if (audio case final ServiceAudioInput input) {
          input.fail('${args['message']}');
        }
      case 'conflict':
        final reason = args['reason'];
        await _serial(
          () => reason is String
              ? _hold('conflict', reason)
              : _release('conflict'),
        );
      case 'overlayClosed':
        await _serial(() => _release('overlay'));
      case 'shutdown':
        await _serial(_shutdown);
    }
    return null;
  }

  // Operations run one after the other, in call order.
  Future<void> _serial(Future<void> Function() op) {
    final next = _ops.then((_) => op());
    _ops = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _run({required bool verify}) async {
    if (_ending) return;
    if (_listener != null && _verify == verify) return;
    await _stopListener();
    _verify = verify;
    final engine = await parts.engine();
    if (engine == null) return _fail('no-templates');
    final listener = WakeWordListener(
      audio: audio,
      engine: _LoggingEngine(engine),
      verifier: verify ? _LoggingVerifier(parts.verifier()) : null,
    );
    _listener = listener;
    _subs
      ..add(listener.detections.listen((d) => unawaited(_onDetection(d))))
      ..add(
        listener.states.listen((s) {
          if (s == WakeListenerState.failed) {
            unawaited(_fail(listener.failure?.kind.name ?? 'failed'));
          }
        }),
      );
    try {
      _holds.clear();
      await listener.start();
    } on Object {
      return; // reported through the state change
    }
    voiceLog('wake-listening', {'verify': verify});
    _alive = Timer.periodic(aliveEvery, (_) => _logAlive());
  }

  void _logAlive() {
    final stats = _listener?.stats;
    if (stats == null) return;
    voiceLog('wake-alive', {
      'cand': stats.candidates,
      'ok': stats.confirmed,
      'candPerH': stats.candidatesPerHour.toStringAsFixed(1),
      'okPerH': stats.confirmedPerHour.toStringAsFixed(1),
      'min': stats.runtime.inMinutes,
    });
  }

  Future<void> _onDetection(WakeWordDetection d) => _serial(() async {
    if (!_verify) voiceLog('wake-verify', {'result': 'skip'});
    // The microphone is free before the overlay records (WP51).
    await _hold('overlay', 'overlay');
    final pcm = d.preRoll;
    await _call('hit', {
      'pcm': pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
      'kw': d.hit.keywordId,
      'score': (d.hit.confidence ?? 0).toStringAsFixed(2),
    });
  });

  Future<void> _hold(String key, String reason) async {
    if (!_holds.add(key) || _holds.length > 1) return;
    voiceLog('wake-pause', {'reason': reason});
    await _listener?.pause();
  }

  Future<void> _release(String key) async {
    if (!_holds.remove(key) || _holds.isNotEmpty) return;
    voiceLog('wake-resume');
    try {
      await _listener?.resume();
    } on Object {
      // A failure shows as a state change.
    }
  }

  Future<void> _fail(String reason) async {
    if (_ending) return;
    _ending = true;
    voiceLog('wake-failed', {'reason': reason});
    await _call('failed', {'reason': reason});
  }

  Future<void> _stopListener() async {
    _alive?.cancel();
    _alive = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final listener = _listener;
    _listener = null;
    await listener?.dispose();
  }

  Future<void> _shutdown() async {
    _ending = true;
    await _stopListener();
    await parts.dispose();
    channel.setMethodCallHandler(null);
  }

  Future<void> _call(String method, [Object? args]) async {
    try {
      await channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // The service is gone.
    } on MissingPluginException {
      // Same.
    }
  }
}

/// Logs every stage 1 candidate: score and rule, nothing else.
final class _LoggingEngine implements WakeWordEngine {
  _LoggingEngine(this.inner);

  final WakeWordEngine inner;

  @override
  Future<void> open(List<KeywordSpec> keywords) => inner.open(keywords);

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    final hits = await inner.accept(frame);
    for (final h in hits) {
      voiceLog('wake-cand', {
        'score': (h.confidence ?? 0).toStringAsFixed(2),
        'rule': h.reason,
      });
    }
    return hits;
  }

  @override
  void reset() => inner.reset();

  @override
  Future<void> close() => inner.close();
}

/// Logs the verdict of stage 2 (`ok`, `no`, or `skip` if it could not
/// decide, which counts as not confirmed).
final class _LoggingVerifier implements WakeVerifier {
  _LoggingVerifier(this.inner);

  final WakeVerifier inner;

  @override
  Future<bool> confirm(Int16List pcm) async {
    try {
      final ok = await inner.confirm(pcm);
      voiceLog('wake-verify', {'result': ok ? 'ok' : 'no'});
      return ok;
    } on Object catch (e) {
      voiceLog('wake-verify', {'result': 'skip', 'error': errorCode(e)});
      return false;
    }
  }
}
