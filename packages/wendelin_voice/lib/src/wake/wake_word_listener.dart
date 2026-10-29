import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../dev/dev_archive.dart';
import '../dev/dev_clips.dart';
import '../dev/wake_shadow_run.dart';
import '../io/audio_input.dart';
import '../io/voice_exception.dart';
import '../models/wake_classifier_catalog.dart';
import 'keyword_spec.dart';
import 'pre_roll_buffer.dart';
import 'wake_archive_notes.dart';
import 'wake_verifier.dart';
import 'wake_verifier_b.dart';
import 'wake_word_engine.dart';

part 'wake_word_listener_candidate.dart';

/// A confirmed wake word.
@immutable
final class WakeWordDetection {
  /// Creates a detection.
  const WakeWordDetection({
    required this.hit,
    required this.preRoll,
    required this.latency,
    this.wakeEnd,
    this.position = 0,
  });

  /// The stage-1 hit.
  final WakeWordHit hit;

  /// Audio from [PreRollBuffer.defaultCapacity] before the end of the hit
  /// (stream position, independent of how late the engine reported it) up to
  /// the moment of confirmation, gap-free (the next utterance may start in
  /// it).
  final Int16List preRoll;

  /// Sample position in [preRoll] where the wake word ends (engine
  /// estimate; `null` if unknown).
  final int? wakeEnd;

  /// Stream position (samples since the microphone was opened) at the end of
  /// [preRoll]: the owner continues the recording there without a gap.
  final int position;

  /// Time between hit and confirmation (stage 2 duration, in audio time).
  final Duration latency;
}

/// Diagnostics without any content: counts and run time.
@immutable
final class WakeWordStats {
  /// Creates the numbers.
  const WakeWordStats({
    required this.candidates,
    required this.confirmed,
    required this.runtime,
  });

  /// Stage-1 candidates that were passed to stage 2.
  final int candidates;

  /// Confirmed wake words.
  final int confirmed;

  /// Audio time listened (from the sample count).
  final Duration runtime;

  /// Candidates per hour of [runtime] (0 below one minute).
  double get candidatesPerHour => _perHour(candidates);

  /// Confirmed per hour of [runtime].
  double get confirmedPerHour => _perHour(confirmed);

  double _perHour(int n) => runtime.inSeconds < 60
      ? 0
      : n * Duration.microsecondsPerHour / runtime.inMicroseconds;

  @override
  String toString() =>
      'WakeWordStats(candidates $candidates, confirmed $confirmed, $runtime)';
}

/// State of the [WakeWordListener].
enum WakeListenerState {
  /// Not started or stopped; microphone released.
  idle,

  /// Microphone open, engine running.
  listening,

  /// Paused; microphone released (e.g. the overlay uses it).
  paused,

  /// Ended by an error in the audio stream or engine; see
  /// [WakeWordListener.failure].
  failed,
}

/// Connects `AudioInput` → engine (stage 1) → verifier (stage 2) →
/// [detections].
final class WakeWordListener {
  /// Creates a listener. Without a [verifier] every candidate counts
  /// (stage 2 disabled).
  WakeWordListener({
    required this.audio,
    required this.engine,
    this.verifier,
    this.keywords = const [KeywordSpec.wendelin],
    this.lockout = const Duration(milliseconds: 1500),
    this.preRoll = AudioRingBuffer.defaultCapacity,
    this.verifyWindow = WakeClassifierRules.verifyWindow,
    this.verifyTail = WakeClassifierRules.verifyTail,
    this.verifyTimeout = const Duration(seconds: 8),
    this.devClips,
    this.nearMissAbove,
  });

  /// Microphone.
  final AudioInput audio;

  /// Stage 1.
  final WakeWordEngine engine;

  /// Stage 2, optional.
  final WakeVerifier? verifier;

  /// Keywords the engine is opened with.
  final List<KeywordSpec> keywords;

  /// Pause after a confirmed or rejected candidate (no double hits).
  final Duration lockout;

  /// Pre-roll length handed to the consumer.
  final Duration preRoll;

  /// Audio before the hit that stage 2 transcribes.
  final Duration verifyWindow;

  /// Audio recorded after the hit before stage 2 starts (the word may still
  /// be ending; Whisper then sees about `verifyWindow + verifyTail`, ~3 s).
  /// Skipped without a verifier. Adds this much latency.
  final Duration verifyTail;

  /// Longest wait for stage 2 (a timeout counts as rejected).
  final Duration verifyTimeout;

  /// Developer mode (WP148): audio of every candidate (`wake-cand`, 2 s each
  /// side) and of every check (`wake-verify`); `null` or off: nothing is kept.
  final DevClips? devClips;

  /// Lowest score of the active detection band (the engine's verify limit):
  /// a window at or above it is a candidate, not a near miss (WP155). The
  /// host passes the band of the engine it runs; default: the phone band.
  final double? nearMissAbove;

  final _detections = StreamController<WakeWordDetection>.broadcast(sync: true);
  final _stateChanges = StreamController<WakeListenerState>.broadcast(
    sync: true,
  );

  /// Minimum ring buffer capacity (WP178: rolling 5–6 s).
  static const minBufferCapacity = Duration(seconds: 5);

  late final AudioRingBuffer _ring = AudioRingBuffer(
    capacity: _max(
      minBufferCapacity,
      _max(preRoll, verifyWindow + verifyTail + const Duration(seconds: 2)),
    ),
  );
  late final _dev = DevAroundSet(devClips);
  // WP155/WP171: one case per utterance from the window values.
  late final double _above =
      nearMissAbove ?? WakeClassifierRules.phone.verifyFrom;
  late final _shadow = WakeShadowRun(above: _above);
  Completer<void>? _tailWait;
  int _tailTarget = 0;
  // Cancelled in stop/_release.
  // ignore: cancel_subscriptions
  StreamSubscription<Int16List>? _sub;
  bool _engineOpen = false;
  WakeListenerState _state = WakeListenerState.idle;
  VoiceException? _failure;
  int _position = 0; // samples fed to the engine
  int _lockedUntil = 0;
  int _candidates = 0;
  int _confirmed = 0;
  int _generation = 0;
  int _processed = 0;
  Future<void> _chain = Future.value();

  /// Samples of audio currently held in memory (ring buffer); 0 after stop or pause.
  @visibleForTesting
  int get bufferedSamples => _ring.length;

  /// Confirmed wake words.
  Stream<WakeWordDetection> get detections => _detections.stream;

  /// State changes.
  Stream<WakeListenerState> get states => _stateChanges.stream;

  /// Current state.
  WakeListenerState get state => _state;

  /// Why the listener is [WakeListenerState.failed].
  VoiceException? get failure => _failure;

  /// Diagnostics (no audio, no text).
  WakeWordStats get stats => WakeWordStats(
    candidates: _candidates,
    confirmed: _confirmed,
    runtime: samplesToDuration(_position),
  );

  /// Opens the engine and the microphone. Errors become
  /// [WakeListenerState.failed] and are rethrown.
  Future<void> start() async {
    if (_state == WakeListenerState.listening) return;
    _failure = null;
    try {
      if (!_engineOpen) {
        await engine.open(keywords);
        _engineOpen = true;
      }
      _listen();
    } on Object catch (e) {
      await _fail(e);
      rethrow;
    }
  }

  void _listen() {
    engine.reset();
    _ring.clear();
    _position = 0;
    _processed = 0;
    _chain = Future.value();
    _lockedUntil = 0;
    _shadow.reset();
    if (devClips?.archive != null) attachWindowSink(engine, _onWindow);
    final gen = ++_generation;
    _sub = audio.start().listen(
      (f) => _onFrame(f, gen),
      onError: (Object e) => unawaited(_fail(e)),
      onDone: () {
        if (_state == WakeListenerState.listening && gen == _generation) {
          unawaited(
            _fail(
              const VoiceException(
                VoiceErrorKind.unavailable,
                'Der Audiostrom wurde unerwartet beendet.',
              ),
            ),
          );
        }
      },
    );
    _setState(WakeListenerState.listening);
  }

  void _onFrame(Int16List frame, int gen) {
    if (gen != _generation) return;
    _ring.add(frame);
    _dev.feed(frame);
    _position += frame.length;
    if (_tailWait != null && _position >= _tailTarget) {
      _tailWait!.complete();
      _tailWait = null;
    }
    // Engine and verifier see the frames strictly in order.
    _chain = _chain.then((_) => _process(frame, gen));
  }

  Future<void> _process(Int16List frame, int gen) async {
    if (gen != _generation) return;
    try {
      final hits = await engine.accept(frame);
      _processed += frame.length;
      if (gen != _generation || hits.isEmpty) return;
      if (_processed < _lockedUntil) return;
      await _onCandidate(hits.first, gen);
    } on Object catch (e) {
      if (gen == _generation) await _fail(e);
    }
  }

  Future<void> _onCandidate(WakeWordHit hit, int gen) async {
    _candidates++;
    final end = hit.endSample;
    final peaks = _shadow.candidate(end);
    final arch = noteWakeCandidate(devClips, hit, shadow: peaks, above: _above);
    _startCandidateClip(end, arch);
    // WP178: Hold buffer during verification so it grows with incoming audio
    // without dropping the candidate audio or subsequent command.
    _ring.hold();
    final tail = verifier == null || hit.direct
        ? 0
        : durationToSamples(verifyTail);
    if (!await _waitForTail(end, tail, gen, arch)) return;

    final res = await _verifyCandidate(hit, end, tail, arch, gen);
    if (gen != _generation) {
      _ring.release(discard: true);
      arch?.finish('dropped', {'reason': 'stopped'});
      return;
    }
    finishWakeCase(arch, res.verdict, res.ok);
    _lockedUntil = _processed + durationToSamples(lockout);
    if (!res.ok) {
      // Discard excess audio older than capacity and resume rolling.
      _ring.release(discard: true);
      return;
    }
    _ring.release(discard: false);
    _confirmed++;
    _emitDetection(hit, end);
  }

  /// Releases the microphone; [resume] continues. No-op unless listening.
  Future<void> pause() async {
    if (_state != WakeListenerState.listening) return;
    await _release();
    _setState(WakeListenerState.paused);
  }

  /// Continues after [pause].
  Future<void> resume() async {
    if (_state != WakeListenerState.paused) return;
    try {
      _listen();
    } on Object catch (e) {
      await _fail(e);
      rethrow;
    }
  }

  /// Stops and releases microphone and engine. The listener can be
  /// [start]ed again.
  Future<void> stop() async {
    await _release();
    if (_engineOpen) {
      _engineOpen = false;
      await engine.close();
    }
    if (_state != WakeListenerState.idle) _setState(WakeListenerState.idle);
  }

  Future<void> _release() async {
    _generation++;
    // What was collected for the developer mode is written, cut short.
    _dev.flush();
    // No audio stays in memory while the microphone is released.
    _ring.clear();
    _tailWait?.complete();
    _tailWait = null;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    await audio.stop();
  }

  Future<void> _fail(Object e) async {
    _failure = e is VoiceException
        ? e
        : VoiceException(
            VoiceErrorKind.failed,
            'Die Wake-Word-Erkennung wurde beendet.',
            cause: e,
          );
    await _release();
    if (_engineOpen) {
      _engineOpen = false;
      try {
        await engine.close();
      } on Object {
        // already failing
      }
    }
    _setState(WakeListenerState.failed);
  }

  void _setState(WakeListenerState s) {
    _state = s;
    if (!_stateChanges.isClosed) _stateChanges.add(s);
  }

  /// Ends the listener for good (closes the streams).
  Future<void> dispose() async {
    await stop();
    await _detections.close();
    await _stateChanges.close();
  }
}

Duration _max(Duration a, Duration b) => a > b ? a : b;
