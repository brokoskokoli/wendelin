import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../dev_archive.dart';
import '../voice_log.dart';
import 'barge_meter.dart';

/// Barge-in detector of the conversation mode (WP50, WP44 Nachtrag 2):
/// while the answer is spoken it listens for „Wendelin“ with the same
/// feature chain and the personal templates as the idle wake word, only
/// stricter ([extraMargin] on every threshold; the own voice from the
/// speaker is the main false trigger). Stage 2 does not run (Whisper is
/// busy speaking along the answer).
///
/// The engine is built at the first [start]: the templates are read then,
/// not when the overlay opens. Without a learned voice the detector stays
/// silent (barge-in by a tap on the microphone still works).
/// WP113: with the check by the big recognizer (stage 2) stage 1 only has to
/// find a candidate, so its thresholds lie below the learned ones. See
/// `docs/notes/barge-stop-verify.md`. (WP134: the „Stopp“ rules were removed.)
const candidateWakeMargin = -0.05;

/// Lowest stage 1 threshold with stage 2 (WP134). A calibrated template
/// threshold can be as low as 0.40; with the margin stage 1 would sit at
/// 0.35, where FLEURS speech alone gives 88 candidates per hour (0.45: 30).
const candidateWakeFloor = 0.45;

final class LazyWakeBargeInDetector
    implements BargeInDetector, SpokenTextSink, BargeTailSource {
  /// Creates the detector on [audio] (the capture profile follows the
  /// pipeline state, see `CaptureProfileFollower`).
  LazyWakeBargeInDetector({
    required this.audio,
    required this.templates,
    required this.features,
    this.extraMargin = 0.05,
    this.verifier,
    this.warm,
    this.onListening,
    this.marginOverride,
    this.diagInterval = const Duration(seconds: 1),
    this.verifySettle = const Duration(milliseconds: 800),
    this.tailMax = const Duration(seconds: 3),
    this.devClips,
    this.onDispose,
  });

  /// Microphone shared with the pipeline.
  final AudioInput audio;

  /// Templates of all learned voices.
  final Future<List<WakeTemplates>> Function() templates;

  /// A new feature chain.
  final WakeFeatureExtractor Function() features;

  /// Added to every template threshold (without [verifier]; with one the
  /// candidate margin [candidateWakeMargin] applies).
  final double extraMargin;

  /// Stage 2 (WP113, K84): builds the check of a candidate by the big
  /// recognizer; gets the text read aloud so far (own voice filter).
  /// `null`: no stage 2, the stage 1 hit interrupts directly.
  final BargeVerifier Function(String Function() spokenText)? verifier;

  /// WP123: the microphone audio before the answer (the tail of the capture,
  /// see `MicTail`); primes the feature chain so the first window comes
  /// after one chunk, not after ~2 s. `null`: cold start.
  final Int16List Function()? warm;

  /// Told when listening starts and ends (the „hört mit“ ring, WP113).
  final void Function({required bool on})? onListening;

  /// Sentences of the echo filter: only the latest ones can be in the clip
  /// of the 2.5 s window, earlier words of the answer must not mute a
  /// keyword (a text that names itself „Wendelin“).
  static const echoSentences = 2;

  final _spoken = <String>[];

  String get _recentSpoken => _spoken.join(' ');

  @override
  void spoke(String sentence) {
    _spoken.add(sentence);
    if (_spoken.length > echoSentences) _spoken.removeAt(0);
  }

  /// Developer setting (WP72, `debug.bargeMargin`): replaces [extraMargin]
  /// when it returns a value. Read once, when the engine is built.
  final Future<double?> Function()? marginOverride;

  /// Wait after a candidate until the check starts (the word is over).
  final Duration verifySettle;

  /// How long the detached recording runs without a follow-up (WP146).
  final Duration tailMax;

  /// WP148: audio of candidates and checks (developer mode only).
  final DevClips? devClips;

  /// Called once when the detector ends for good (WP151: releases what the
  /// verifier holds).
  final Future<void> Function()? onDispose;

  /// Interval of the `barge-diag` lines while listening.
  final Duration diagInterval;

  BargeMeter? _meter;
  Timer? _diag;

  WakeWordBargeInDetector? _inner;
  bool _empty = false;
  bool _running = false;
  bool _disposeWhenIdle = false;
  bool _disposed = false;
  StreamSubscription<BargeInSignal>? _sub;
  final _signals = StreamController<BargeInSignal>.broadcast(sync: true);

  @override
  Stream<BargeInSignal> get signals => _signals.stream;

  @override
  bool get isRunning => _running;

  @override
  Future<void> start() async {
    // A tail that ended on its own (time out) left the inner detector idle.
    if (_running && _inner?.isRunning != false) return;
    _running = true;
    if (_inner == null && !_empty) {
      final sets = await templates();
      if (sets.isEmpty) {
        _empty = true;
        voiceLog('barge-in-off', {'reason': 'no-templates'});
      } else {
        _inner = await _build(sets);
      }
    }
    // A stop during the loading wins.
    if (_running) {
      _meter?.reset();
      await _inner?.start();
      voiceLog('barge-listen', {'on': _inner != null});
      if (_inner != null && _running) {
        onListening?.call(on: true);
        _diag?.cancel();
        _diag = Timer.periodic(diagInterval, (_) => _meter?.flush());
      }
    }
  }

  /// Builds the engine and the detector from the templates (stage 1 with the
  /// candidate margins, stage 2 when a [verifier] is set).
  Future<WakeWordBargeInDetector> _build(List<WakeTemplates> sets) async {
    final override = await marginOverride?.call();
    final staged = verifier != null;
    final margin = override ?? (staged ? candidateWakeMargin : extraMargin);
    final strict = [
      for (final t in sets)
        t.withThreshold(
          (t.threshold + margin).clamp(
            staged && override == null ? candidateWakeFloor : 0.0,
            0.99,
          ),
        ),
    ];
    final meter = _meter = BargeMeter(
      threshold: strict.map((t) => t.threshold).reduce((a, b) => a < b ? a : b),
    );
    voiceLog('barge-config', {
      'margin': margin,
      'verify': staged,
      'thr': meter.threshold,
    });
    // WP155: the wake archive stores the settings of the engine.
    devArchiveSetInfo('barge', {
      'mode': 'conversation',
      'margin': margin,
      'verify': staged,
      'thr': meter.threshold,
    });
    final engine = CandidateWakeEngine(
      features: features(),
      templates: strict.first,
      moreTemplates: strict.skip(1).toList(),
      modelThreshold: null,
      // WP134: also without stage 2 (switch off) a silent stream after the
      // warm start must not fire; templates look like silence (WP126/129).
      silenceFloor: WakeClassifierRules.silenceFloor(),
      onWindow: (main, _) => meter.onWindow(main),
    );
    final inner = WakeWordBargeInDetector(
      audio: MeteredAudioInput(audio, meter),
      engine: MeteredEngine(engine, meter),
      verifier: verifier?.call(() => _recentSpoken),
      warm: warm,
      tailMax: tailMax,
      settle: verifySettle,
      devClips: devClips,
      // Scores and kind only; the word itself stays out of the log.
      onCandidate: (kind, {required busy, required score}) =>
          voiceLog('barge-cand', {
            'kind': kind.name,
            'busy': busy,
            // WP151: the candidate's own score; `sim` is the best of the
            // session (not necessarily this candidate's).
            'cand': score.toStringAsFixed(2),
            ...meter.maxima,
          }),
      onVerdict: (v, ms) => voiceLog('barge-verify', {
        'result': v.result,
        'ms': ms,
        if (v.reason != null) 'reason': v.reason,
        // WP151: who decided and, for B, with which score.
        if (v.verifier != null) 'verifier': v.verifier,
        if (v.score != null) 'score': v.score!.toStringAsFixed(4),
      }),
    );
    _sub = inner.signals.listen((signal) {
      // Every hit leaves a line, with the best similarities so far.
      voiceLog('barge-hit', {'kind': signal.code, ...?_meter?.maxima});
      _signals.add(signal);
    });
    return inner;
  }

  // WP146: see `BargeTailSource`; without an engine there is no recording.
  @override
  bool beginTail() {
    final begun = _inner?.beginTail() ?? false;
    // Nothing is detected any more: the „hört mit“ ring goes off.
    if (begun) onListening?.call(on: false);
    return begun;
  }

  @override
  BargeTail? endTail() {
    final tail = _inner?.endTail();
    // The inner detector ends its recording itself; this one follows.
    if (tail != null) unawaited(stop());
    return tail;
  }

  @override
  Future<void> stop() async {
    _running = false;
    _diag?.cancel();
    _diag = null;
    _spoken.clear();
    await _inner?.stop();
    if (_inner != null) _meter?.summary();
    voiceLog('barge-listen', {'on': false});
    onListening?.call(on: false);
    if (_disposeWhenIdle) await dispose();
  }

  /// Ends the detector as soon as it is idle: a running listening session
  /// (the spoken answer) is not cut off by a rebuild of the provider
  /// (a new or deleted voice takes effect at the next start).
  Future<void> disposeWhenIdle() async {
    if (_running) {
      _disposeWhenIdle = true;
      return;
    }
    await dispose();
  }

  /// Ends the detector for good.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final wasRunning = _running;
    _running = false;
    _diag?.cancel();
    // Ended without stop(): the summary still belongs in the log.
    if (wasRunning && _inner != null) {
      _meter?.summary();
      onListening?.call(on: false);
    }
    await _sub?.cancel();
    await _inner?.dispose();
    await _signals.close();
    await onDispose?.call();
  }
}
