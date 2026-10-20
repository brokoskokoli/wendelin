import 'dart:async';
import 'dart:typed_data';

import '../io/audio_input.dart';
import '../io/barge_in_detector.dart';
import 'barge_verifier.dart';
import 'keyword_spec.dart';
import 'pre_roll_buffer.dart';
import 'wake_word_engine.dart';

/// [BargeInDetector] on a [WakeWordEngine]: while the answer is spoken it
/// listens on [audio] for the keywords `wake` and `stop` (concept K23 c).
///
/// The engine should run with a stricter threshold than the idle listener.
/// [stop] cancels the stream and calls `audio.stop()` **before** it returns,
/// (the engine stays open for the next [start]; [dispose] closes it)
/// so the owner can switch the capture profile back to speech recognition
/// (`VOICE_RECOGNITION`) before the follow-up window opens (WP51 „Offen“).
final class WakeWordBargeInDetector implements BargeInDetector {
  /// Creates the detector.
  WakeWordBargeInDetector({
    required this.audio,
    required this.engine,
    this.keywords = const [KeywordSpec.wendelin],
    this.verifier,
    this.clip = const Duration(milliseconds: 2500),
    this.cooldown = const Duration(milliseconds: 1500),
    this.verifyTimeout = const Duration(seconds: 6),
    this.onCandidate,
    this.onVerdict,
  });

  /// Stage 2 (WP113, K84): with a [verifier] a hit of the engine is only a
  /// candidate. The audio of the last [clip] goes to the verifier and the
  /// signal follows only if it recognizes the word. Without one the hit is
  /// the signal.
  final BargeVerifier? verifier;

  /// Audio handed to the [verifier] (at most 5 s).
  final Duration clip;

  /// No new check this long after one ended without a keyword (CPU: the
  /// own voice makes many candidates).
  final Duration cooldown;

  /// A check that takes longer counts as failed (fail closed).
  final Duration verifyTimeout;

  /// Called for every stage 1 candidate; [busy]: a check is running or in
  /// cooldown, the candidate is dropped.
  final void Function(BargeInKeyword candidate, {required bool busy})?
  onCandidate;

  /// Called with the verdict and the time of the check in ms.
  final void Function(BargeVerdict verdict, int ms)? onVerdict;

  /// Microphone (capture profile for speech output, set by the app).
  final AudioInput audio;

  /// Keyword engine.
  final WakeWordEngine engine;

  /// Keywords to open the engine with.
  final List<KeywordSpec> keywords;

  final _signals = StreamController<BargeInSignal>.broadcast(sync: true);
  // Cancelled in stop/_release.
  // ignore: cancel_subscriptions
  StreamSubscription<Int16List>? _sub;
  bool _running = false;
  bool _engineOpen = false;
  int _generation = 0;
  late final PreRollBuffer _ring = PreRollBuffer(capacity: clip);
  bool _verifying = false;
  int _fed = 0, _blockedUntil = 0;
  Future<void> _chain = Future.value();
  Future<void> _lifecycle = Future.value();

  @override
  Stream<BargeInSignal> get signals => _signals.stream;

  @override
  bool get isRunning => _running;

  // start and stop run one after the other, in call order.
  Future<void> _serial(Future<void> Function() job) {
    final next = _lifecycle.then((_) => job());
    _lifecycle = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> start() => _serial(() async {
    if (_running) return;
    if (!_engineOpen) {
      await engine.open(keywords);
      _engineOpen = true;
    }
    engine.reset();
    _ring.clear();
    _fed = _blockedUntil = 0;
    final gen = ++_generation;
    _chain = Future.value();
    _sub = audio.start().listen(
      (f) => _chain = _chain.then((_) => _onFrame(f, gen)),
      onError: (Object _) => unawaited(stop()),
    );
    _running = true;
  });

  Future<void> _onFrame(Int16List frame, int gen) async {
    if (gen != _generation) return;
    if (verifier != null) _ring.add(frame);
    _fed += frame.length;
    final hits = await engine.accept(frame);
    if (gen != _generation) return;
    for (final h in hits) {
      final keyword = switch (h.keywordId) {
        'stop' => BargeInKeyword.stop,
        'wake' => BargeInKeyword.wake,
        _ => null,
      };
      if (keyword == null) continue;
      final v = verifier;
      if (v == null) {
        _signals.add(BargeInSignal.keyword(keyword));
        continue;
      }
      final busy = _verifying || _fed < _blockedUntil;
      onCandidate?.call(keyword, busy: busy);
      if (!busy) unawaited(_verify(v, keyword, gen));
    }
  }

  Future<void> _verify(BargeVerifier v, BargeInKeyword cand, int gen) async {
    _verifying = true;
    final pcm = _ring.snapshot();
    final sw = Stopwatch()..start();
    var verdict = const BargeVerdict('skip');
    try {
      verdict = await v.verify(pcm, candidate: cand).timeout(verifyTimeout);
    } on Object catch (_) {
      // Fail closed: no verdict, no keyword.
    }
    _verifying = false;
    if (gen != _generation) return;
    onVerdict?.call(verdict, sw.elapsedMilliseconds);
    final keyword = verdict.keyword;
    if (keyword == null) {
      _blockedUntil = _fed + durationToSamples(cooldown);
      return;
    }
    _signals.add(BargeInSignal.keyword(keyword));
  }

  @override
  Future<void> stop() => _serial(() async {
    if (!_running) return;
    _running = false;
    _generation++;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    await audio.stop();
  });

  /// Stops and closes the engine for good.
  Future<void> dispose() async {
    await stop();
    await _serial(() async {
      if (!_engineOpen) return;
      _engineOpen = false;
      await engine.close();
    });
  }
}
