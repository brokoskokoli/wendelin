import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import '../channels.dart';
import 'service_audio_input.dart';
import 'wake_detector.dart';

export '../channels.dart' show wakeEngineChannelName;

/// What the wake word host needs from the device (replaced in tests).
abstract interface class WakeParts {
  /// Stage 1 for all learned voices; `null` if nothing is learned. WP129:
  /// [detector] chooses templates or the trained classifier, [station] the
  /// score band of the place; the classifier throws if its model is missing.
  Future<WakeWordEngine?> engine({
    WakeDetector detector = WakeDetector.templates,
    bool station = false,
  });

  /// Stage 2; loads the recognizer when needed and frees it again. With the
  /// classifier ([detector] `model`) Parakeet is preferred, Whisper is the
  /// fallback; the template path always uses Whisper.
  WakeVerifier verifier({WakeDetector detector = WakeDetector.templates});

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
  _LoggingVerifier? _verifier;
  WakeDetector _detector = WakeDetector.templates;
  bool _station = false;
  bool _started = false;
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
        await _serial(
          () => _run(
            verify: args['verify'] != false,
            choice: WakeDetectorChoice.parse(args['detector']),
            station: args['station'] == true,
          ),
        );
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

  Future<void> _run({
    required bool verify,
    WakeDetectorChoice choice = WakeDetectorChoice.auto,
    bool station = false,
  }) async {
    if (_ending) return;
    final detector = choice.resolve(station: station);
    if (_listener != null &&
        _verify == verify &&
        _detector == detector &&
        _station == station) {
      return;
    }
    await _stopListener();
    _verify = verify;
    _detector = detector;
    _station = station;
    _started = false;
    final WakeWordEngine? engine;
    try {
      engine = await parts.engine(detector: detector, station: station);
    } on Object catch (e) {
      // The classifier without its model (WP140): the learned voice takes
      // over if there is one; without it the service ends and the settings
      // say why.
      if (e is VoiceException &&
          e.kind == VoiceErrorKind.modelMissing &&
          await _fallBackToTemplates(verify: verify, detector: detector)) {
        return;
      }
      return _fail(e is VoiceException ? e.kind.name : 'engine-failed');
    }
    if (engine == null) return _fail('no-templates');
    await _startListener(engine, verify: verify);
  }

  Future<void> _startListener(
    WakeWordEngine engine, {
    required bool verify,
  }) async {
    final listener = WakeWordListener(
      audio: audio,
      engine: _LoggingEngine(engine, _detector, verify: verify),
      verifier: verify
          ? _verifier = _LoggingVerifier(parts.verifier(detector: _detector))
          : null,
      // Room noise before the word (WP73): `speechAfterWakeWord` measures
      // its threshold there. The overlay skips everything up to the end of
      // the word, so the longer lead costs nothing but a few KB.
      preRoll: wakePreRoll,
    );
    _listener = listener;
    _subs
      ..add(listener.detections.listen((d) => unawaited(_onDetection(d))))
      ..add(
        listener.states.listen((s) {
          if (s == WakeListenerState.failed) {
            final kind = listener.failure?.kind;
            unawaited(
              _serial(() async {
                // The model file is checked when the chain opens: same
                // fallback as above.
                if (kind == VoiceErrorKind.modelMissing &&
                    _listener == listener &&
                    await _fallBackToTemplates(
                      verify: verify,
                      detector: _detector,
                    )) {
                  return;
                }
                await _fail(kind?.name ?? 'failed');
              }),
            );
          }
        }),
      );
    try {
      // Holds (call, other recording, overlay) survive a new `run`: the
      // microphone stays closed until the last one is released.
      if (_holds.isNotEmpty) return;
      await _begin(listener);
    } on Object {
      return; // reported through the state change
    }
  }

  /// The classifier is missing: run on the templates instead (`true` if
  /// that works). Not for a run that already is on the templates.
  Future<bool> _fallBackToTemplates({
    required bool verify,
    required WakeDetector detector,
  }) async {
    if (detector != WakeDetector.model || _ending) return false;
    final WakeWordEngine? templates;
    try {
      templates = await parts.engine(
        detector: WakeDetector.templates,
        station: _station,
      );
    } on Object {
      return false;
    }
    if (templates == null) return false;
    voiceLog('wake-fallback', {'from': 'model', 'reason': 'model-missing'});
    await _stopListener();
    _detector = WakeDetector.templates;
    _started = false;
    await _startListener(templates, verify: verify);
    return true;
  }

  Future<void> _begin(WakeWordListener listener) async {
    _started = true;
    await listener.start();
    voiceLog('wake-listening', {
      'verify': _verify,
      'detector': _detector.name,
      'station': _station,
    });
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
    // Which stage decided: a sure classifier hit (1), the transcript (2), or
    // nothing checked (stage 2 off). Counting FA/h and hits per stage.
    voiceLog('wake-hit-stage', {
      'detector': _detector.name,
      'stage': d.hit.direct
          ? '1-direct'
          : _verify
          ? '2-verified'
          : '1-unchecked',
      'score': (d.hit.score ?? d.hit.confidence ?? 0).toStringAsFixed(3),
      // Which recognizer decided stage 2 (parakeet, whisper); `none` if none.
      'verifier': !d.hit.direct && _verify ? _verifier?.kind ?? 'none' : 'none',
    });
    if (!_verify && !d.hit.direct) {
      voiceLog('wake-verify', {'result': 'skip'});
    }
    final pcm = d.preRoll;
    // The service keeps the microphone open from the end of `pcm` on until
    // the overlay takes the audio and opens its own (WP68, WP51: never two
    // recordings at once). So `hit` goes first: the `stopMic` of the pause
    // below then arrives at a service that is already collecting and is
    // ignored.
    await _call('hit', {
      'pcm': pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
      // Where the wake word ends in `pcm` and where the stream stands at its
      // end: the service keeps recording from there (WP68).
      'end': d.wakeEnd ?? 0,
      'pos': d.position,
      'kw': d.hit.keywordId,
      'score': (d.hit.confidence ?? 0).toStringAsFixed(2),
    });
    await _hold('overlay', 'overlay');
  });

  Future<void> _hold(String key, String reason) async {
    if (!_holds.add(key) || _holds.length > 1) return;
    voiceLog('wake-pause', {'reason': reason});
    if (_started) await _listener?.pause();
  }

  Future<void> _release(String key) async {
    if (!_holds.remove(key) || _holds.isNotEmpty) return;
    voiceLog('wake-resume');
    try {
      final listener = _listener;
      if (listener != null && !_started) {
        await _begin(listener);
      } else {
        await listener?.resume();
      }
    } on Object {
      // A failure shows as a state change.
    }
  }

  Future<void> _fail(String reason) async {
    if (_ending) return;
    _ending = true;
    // The log allows lower-case codes only: `modelMissing` → `model-missing`.
    final code = reason.replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '-${m[0]!.toLowerCase()}',
    );
    voiceLog('wake-failed', {'reason': code});
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

/// Audio before the wake word end handed to the overlay: the word (up to
/// about a second) and room noise before it.
const wakePreRoll = Duration(milliseconds: 2500);

/// Logs every stage 1 candidate: score and rule, nothing else.
final class _LoggingEngine implements WakeWordEngine {
  _LoggingEngine(this.inner, this.detector, {required this.verify});

  final WakeWordEngine inner;
  final WakeDetector detector;

  /// Whether stage 2 runs (else a candidate below `acceptFrom` goes on
  /// `unchecked`).
  final bool verify;

  @override
  Future<void> open(List<KeywordSpec> keywords) => inner.open(keywords);

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    final hits = await inner.accept(frame);
    for (final h in hits) {
      voiceLog('wake-cand', {
        'stage': 1,
        'detector': detector.name,
        'score': (h.score ?? h.confidence ?? 0).toStringAsFixed(3),
        'rule': h.reason,
        'direct': h.direct,
      });
      // WP141: how long stage 1 held the score and where the candidate goes
      // on; also for candidates stage 2 rejects later (`wake-verify`).
      voiceLog('wake-decision', {
        'hold_ms': h.holdMs ?? 0,
        'peak': (h.score ?? h.confidence ?? 0).toStringAsFixed(3),
        'path': h.direct ? 'direct' : (verify ? 'stage2' : 'unchecked'),
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
  String get kind => inner.kind;

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
