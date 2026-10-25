import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../io/audio_input.dart';
import '../io/barge_in_detector.dart';
import 'barge_clip.dart';
import 'barge_tail_collector.dart';
import 'barge_verifier.dart';
import 'keyword_spec.dart';
import 'pre_roll_buffer.dart';
import 'wake_word_engine.dart';

/// [BargeInDetector] on a [WakeWordEngine]: while the answer is spoken it
/// listens on [audio] for the keyword `wake` (concept K23 c; the spoken
/// „Stopp“ was removed in WP134).
///
/// The engine should run with a stricter threshold than the idle listener.
/// [stop] cancels the stream and calls `audio.stop()` **before** it returns,
/// (the engine stays open for the next [start]; [dispose] closes it)
/// so the owner can switch the capture profile back to speech recognition
/// (`VOICE_RECOGNITION`) before the follow-up window opens (WP51 „Offen“).
///
/// With a [DetachableAudioInput] it is also a [BargeTailSource] (WP146).
final class WakeWordBargeInDetector
    implements BargeInDetector, BargeTailSource {
  /// Creates the detector.
  WakeWordBargeInDetector({
    required this.audio,
    required this.engine,
    this.keywords = const [KeywordSpec.wendelin],
    this.verifier,
    this.warm,
    this.warmSpan = const Duration(milliseconds: 1500),
    this.clip = const Duration(milliseconds: 2500),
    this.cooldown = const Duration(milliseconds: 1500),
    this.settle = const Duration(milliseconds: 800),
    this.minLevel = 150,
    this.verifyTimeout = const Duration(seconds: 6),
    this.onCandidate,
    this.onVerdict,
    this.clock = const SystemClock(),
    this.tailMax = const Duration(seconds: 3),
  });

  /// Time source of the tail's idle time.
  final Clock clock;

  /// The longest the recording goes on after the answer (WP146). The
  /// follow-up microphone opened in 0.5 to 1 s on the device (the call path
  /// of the answer is given back first, at most 1 s); a recording that has
  /// no first frame after 3 s failed, and two recordings must never stay on.
  final Duration tailMax;

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

  /// Audio a feature window reaches back (16 windows of 80 ms = 1.28 s, plus
  /// a margin). With a warm start a hit counts only when its window holds
  /// no loud audio of the lead-in any more: the end of the user's command
  /// (`endSilence` ~800 ms of quiet follows it) must not stop the answer.
  /// So the first hits are ignored for `speech end + warmSpan - lead-in`
  /// (~0.7 s live audio with the usual 800 ms of silence).
  final Duration warmSpan;

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
  /// (`skip`/`silent`). With a [verifier] a candidate also counts only if the
  /// live audio held such a block within the last [warmSpan] (the reach of a
  /// feature window). WP126: the device log showed a silent stream (rms 0)
  /// producing a main-word candidate (sim 0.83 > thr 0.75) that
  /// stage 2 would have heard; silence embeddings look like the
  /// templates. This gate closes that gap. 150 is the
  /// level of the [SpeechGate] and the clip check: speech reads 800..1300 rms,
  /// the silent AEC stream 0 and room noise ~12 (local logs).
  final int minLevel;

  /// A check that takes longer counts as failed (fail closed).
  final Duration verifyTimeout;

  /// Called for every stage 1 candidate; [busy]: a check is running or in
  /// cooldown, the candidate is kept and checked again afterwards. A candidate whose confidence is
  /// [strongerMargin] above the one just rejected is not busy in the
  /// cooldown: it gets its own check (WP126).
  final void Function(BargeInKeyword candidate, {required bool busy})?
  onCandidate;

  /// Confidence a candidate must exceed the one rejected last by to skip
  /// the cooldown (log: echo `stop=0.85`, the real word `0.96`).
  static const strongerMargin = 0.05;

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
  late final PreRollBuffer _ring = PreRollBuffer(capacity: clip + clip);
  bool _verifying = false;
  int _fed = 0, _blockedUntil = 0, _ignoreUntil = 0;
  // End of the last live block with speech level, and the confidence of the
  // candidate whose check ended without a keyword (the cooldown holds it).
  int _lastLoud = -1 << 40;
  double _rejected = 0;
  // Candidate waiting for the end of its word (-1: none), and the best one
  // that came during a check or the cooldown.
  int _pendingAt = -1, _deferredAt = 0;
  double _deferredScore = 0, _pendingScore = 0, _checkedScore = 0;
  BargeInKeyword? _pendingKind, _deferredKind;
  Future<void> _chain = Future.value();
  Future<void> _lifecycle = Future.value();

  // Tail after the answer (WP146) and the function that ends the detached
  // recording.
  late final _tail = BargeTailCollector(clock, tailMax);
  Future<void> Function()? _detached;

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
    _fed = _blockedUntil = _ignoreUntil = 0;
    _lastLoud = -1 << 40;
    _rejected = 0;
    _pendingAt = -1;
    _pendingKind = _deferredKind = null;
    _deferredScore = _pendingScore = _checkedScore = 0;
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
      final guard =
          speechEnd(pcm, minLevel) + durationToSamples(warmSpan) - pcm.length;
      _ignoreUntil = guard > 0 ? guard : 0;
    }
    _sub = audio.start().listen((f) {
      if (_tail.active) {
        _tail.add(f);
      } else {
        _chain = _chain.then((_) => _onFrame(f, gen));
      }
    }, onError: (Object _) => unawaited(stop()));
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
    if (verifier != null) {
      _ring.add(frame);
      final loud = speechEnd(frame, minLevel);
      if (loud > 0) _lastLoud = _fed + loud;
    }
    _fed += frame.length;
    final hits = await engine.accept(frame);
    if (gen != _generation) return;
    for (final h in hits) {
      // The window still reaches into the user's command (warm start).
      if (_fed < _ignoreUntil) continue;
      if (h.keywordId != 'wake') continue;
      const keyword = BargeInKeyword.wake;
      if (verifier == null) {
        _signals.add(const BargeInSignal.keyword(keyword));
        continue;
      }
      // WP126: no speech-level sound in the reach of the window.
      if (_fed - _lastLoud > durationToSamples(warmSpan)) {
        onVerdict?.call(const BargeVerdict('skip', null, 'silent'), 0);
        continue;
      }
      // After a rejected check the cooldown holds only candidates that are
      // not clearly stronger (an echo must not shadow the real word).
      final score = h.confidence ?? 0;
      final stronger = score > _rejected + strongerMargin;
      final busy = _verifying || (_fed < _blockedUntil && !stronger);
      onCandidate?.call(keyword, busy: busy);
      if (busy) {
        // The window follows the strongest busy candidate; a weaker later one
        // must not push it back.
        if (_deferredKind == null || score > _deferredScore) _deferredAt = _fed;
        _deferredKind = keyword;
        if (score > _deferredScore) _deferredScore = score;
      } else {
        // Waiting (or already waiting): the check starts after the word.
        _pendingKind = keyword;
        if (score > _pendingScore) _pendingScore = score;
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
      final score = _deferredScore;
      _deferredScore = 0;
      if (_fed - _deferredAt <= durationToSamples(clip)) {
        _pendingKind = kind;
        if (score > _pendingScore) _pendingScore = score;
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
      _checkedScore = _pendingScore;
      _pendingScore = 0;
      unawaited(_verify(v, kind, gen));
    }
  }

  Future<void> _verify(BargeVerifier v, BargeInKeyword cand, int gen) async {
    final pcm = clipEndingAtSpeech(
      _ring.snapshot(),
      fed: _fed,
      lastLoud: _lastLoud,
      settle: settle,
      clip: clip,
    );
    if (speechEnd(pcm, minLevel) == 0) {
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
      _rejected = _checkedScore;
      // A candidate that came meanwhile is checked once the cooldown ends,
      // if its word is still inside the clip; a clearly stronger one (the
      // real word after an echo) right after its own settle time.
      final kind = _deferredKind;
      final deferredScore = _deferredScore;
      _deferredKind = null;
      _deferredScore = 0;
      var at = _blockedUntil > _fed ? _blockedUntil : _fed;
      if (deferredScore > _checkedScore + strongerMargin) {
        final own = _deferredAt + durationToSamples(settle);
        at = own > _fed ? own : _fed;
      }
      if (kind != null && at - _deferredAt <= durationToSamples(clip)) {
        _pendingKind = kind;
        if (deferredScore > _pendingScore) _pendingScore = deferredScore;
        _pendingAt = at;
      }
      return;
    }
    _deferredKind = null;
    _deferredScore = 0;
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
    _deferredScore = _pendingScore = 0;
    final sub = _sub;
    _sub = null;
    final detached = _detached;
    _detached = null;
    _tail.clear();
    await sub?.cancel();
    // A detached recording is not the input's current one: end that one.
    if (detached != null) {
      await detached();
    } else {
      await audio.stop();
    }
  });

  @override
  bool beginTail() {
    final input = audio;
    if (!_running || _tail.active || input is! DetachableAudioInput) {
      return false;
    }
    final end = input.detach();
    if (end == null) return false;
    _detached = end;
    // Pending candidates and checks are void: nobody speaks to an answer
    // that is over, and the engine gets no more frames.
    _generation++;
    _pendingAt = -1;
    _pendingKind = _deferredKind = null;
    _deferredScore = _pendingScore = 0;
    _tail.begin(() => unawaited(stop()));
    return true;
  }

  @override
  BargeTail? endTail() {
    if (!_tail.active) return null;
    final tail = _tail.take();
    // The recording ends now; `stop` ends the detached one.
    unawaited(stop());
    return tail;
  }

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
