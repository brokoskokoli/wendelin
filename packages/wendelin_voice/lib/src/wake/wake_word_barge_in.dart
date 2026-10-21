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
    this.warm,
    this.clip = const Duration(milliseconds: 2500),
    this.cooldown = const Duration(milliseconds: 1500),
    this.settle = const Duration(milliseconds: 800),
    this.minLevel = 150,
    this.verifyTimeout = const Duration(seconds: 6),
    this.onCandidate,
    this.onVerdict,
  });

  /// Stage 2 (WP113, K84): with a [verifier] a hit of the engine is only a
  /// candidate. The audio of the last [clip] goes to the verifier and the
  /// signal follows only if it recognizes the word. Without one the hit is
  /// the signal.
  final BargeVerifier? verifier;

  /// WP123 warm start: the microphone audio shortly before the start (not
  /// the answer). It fills the feature chain of a [WarmableWakeEngine] before
  /// the live frames, so the first window is rated after one chunk instead of
  /// ~2 s. Hits in it are ignored. `null`/empty: cold start.
  final Int16List Function()? warm;

  /// Audio handed to the [verifier] (at most 5 s).
  final Duration clip;

  /// No new check this long after one ended without a keyword (CPU: the
  /// own voice makes many candidates).
  final Duration cooldown;

  /// Wait after a candidate before the check starts: the word is over then
  /// and inside the clip (the stage 1 hit comes while the word starts or
  /// ends, device finding 2026-10-21). Candidates in between are merged.
  final Duration settle;

  /// Smallest level (RMS of a 20 ms block, 16-bit samples) the clip must
  /// reach; a quieter clip is skipped without the recognizer
  /// (`skip`/`silent`).
  final int minLevel;

  /// A check that takes longer counts as failed (fail closed).
  final Duration verifyTimeout;

  /// Called for every stage 1 candidate; [busy]: a check is running or in
  /// cooldown, the candidate is kept and checked again afterwards (the best
  /// one, `stop` before `wake`).
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
  // Candidate waiting for the end of its word (-1: none), and the best one
  // that came during a check or the cooldown.
  int _pendingAt = -1, _deferredAt = 0;
  BargeInKeyword? _pendingKind, _deferredKind;
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
    _pendingAt = -1;
    _pendingKind = _deferredKind = null;
    _verifying = false;
    final gen = ++_generation;
    _chain = Future.value();
    final e = engine;
    Int16List? pcm;
    try {
      pcm = warm?.call();
    } on Object {
      // Fail soft: cold start.
    }
    if (pcm != null && pcm.isNotEmpty && e is WarmableWakeEngine) {
      // The live frames queue behind it (same chain), none is lost.
      _chain = _warmUp(e, pcm, gen);
    }
    _sub = audio.start().listen(
      (f) => _chain = _chain.then((_) => _onFrame(f, gen)),
      onError: (Object _) => unawaited(stop()),
    );
    _running = true;
  });

  Future<void> _warmUp(WarmableWakeEngine e, Int16List pcm, int gen) async {
    const step = 1280;
    try {
      for (var i = 0; i < pcm.length && gen == _generation; i += step) {
        final end = i + step < pcm.length ? i + step : pcm.length;
        await e.warmUp(Int16List.sublistView(pcm, i, end));
      }
    } on Object {
      // Fail soft: a cold chain is the old behavior.
    }
  }

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
      if (verifier == null) {
        _signals.add(BargeInSignal.keyword(keyword));
        continue;
      }
      final busy = _verifying || _fed < _blockedUntil;
      onCandidate?.call(keyword, busy: busy);
      if (busy) {
        _deferredKind = _best(_deferredKind, keyword);
        _deferredAt = _fed;
      } else {
        // Waiting (or already waiting): the check starts after the word.
        _pendingKind = _best(_pendingKind, keyword);
        if (_pendingAt < 0) _pendingAt = _fed + durationToSamples(settle);
      }
    }
    final v = verifier;
    // A candidate from the cooldown (after a check): once the cooldown is
    // over it is checked, if its word is still inside the clip.
    if (v != null &&
        !_verifying &&
        _fed >= _blockedUntil &&
        _deferredKind != null) {
      final kind = _deferredKind!;
      _deferredKind = null;
      if (_fed - _deferredAt <= durationToSamples(clip)) {
        _pendingKind = _best(_pendingKind, kind);
        if (_pendingAt < 0) {
          final after = _deferredAt + durationToSamples(settle);
          _pendingAt = after > _fed ? after : _fed;
        }
      }
    }
    if (v != null && _pendingAt >= 0 && _fed >= _pendingAt && !_verifying) {
      final kind = _pendingKind!;
      _pendingAt = -1;
      _pendingKind = null;
      unawaited(_verify(v, kind, gen));
    }
  }

  static BargeInKeyword _best(BargeInKeyword? a, BargeInKeyword b) =>
      a == BargeInKeyword.stop || b == BargeInKeyword.stop
      ? BargeInKeyword.stop
      : b;

  bool _quiet(Int16List pcm) {
    const block = 320;
    for (var i = 0; i < pcm.length; i += block) {
      final end = i + block < pcm.length ? i + block : pcm.length;
      var sum = 0.0;
      for (var j = i; j < end; j++) {
        sum += pcm[j] * pcm[j];
      }
      if (sum / (end - i) >= minLevel * minLevel) return false;
    }
    return true;
  }

  Future<void> _verify(BargeVerifier v, BargeInKeyword cand, int gen) async {
    final pcm = _ring.snapshot();
    if (_quiet(pcm)) {
      // Nothing to recognize (background similarity): no recognizer run.
      onVerdict?.call(const BargeVerdict('skip', null, 'silent'), 0);
      return;
    }
    _verifying = true;
    final sw = Stopwatch()..start();
    var verdict = const BargeVerdict('skip', null, 'error');
    try {
      verdict = await v.verify(pcm, candidate: cand).timeout(verifyTimeout);
    } on TimeoutException catch (_) {
      verdict = const BargeVerdict('skip', null, 'timeout');
    } on Object catch (_) {
      // Fail closed: no verdict, no keyword.
    }
    _verifying = false;
    if (gen != _generation) {
      // Ended meanwhile: no signal, but visible in the log.
      onVerdict?.call(
        const BargeVerdict('skip', null, 'stopped'),
        sw.elapsedMilliseconds,
      );
      return;
    }
    onVerdict?.call(verdict, sw.elapsedMilliseconds);
    final keyword = verdict.keyword;
    if (keyword == null) {
      _blockedUntil = _fed + durationToSamples(cooldown);
      // A candidate that came meanwhile is checked once the cooldown ends,
      // if its word is still inside the clip.
      final kind = _deferredKind;
      _deferredKind = null;
      final at = _blockedUntil > _fed ? _blockedUntil : _fed;
      if (kind != null && at - _deferredAt <= durationToSamples(clip)) {
        _pendingKind = _best(_pendingKind, kind);
        _pendingAt = at;
      }
      return;
    }
    _deferredKind = null;
    _signals.add(BargeInSignal.keyword(keyword));
  }

  @override
  Future<void> stop() => _serial(() async {
    if (!_running) return;
    _running = false;
    _generation++;
    if (_pendingKind != null) {
      onVerdict?.call(const BargeVerdict('skip', null, 'stopped'), 0);
    }
    _pendingAt = -1;
    _pendingKind = _deferredKind = null;
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
