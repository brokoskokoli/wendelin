import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_core/wendelin_core.dart';

import '../dev/dev_clips.dart';
import '../io/audio_input.dart';
import '../io/barge_in_detector.dart';
import 'barge_candidates.dart';
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
    DevClips? devClips, // WP148: audio of candidates and checks
  }) : _dev = DevAroundSet(devClips);

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

  /// Called for every stage 1 candidate with its [score] (the confidence of
  /// the engine, WP151); [busy]: a check is running or in
  /// cooldown, the candidate is kept and checked again afterwards. A candidate whose confidence is
  /// [strongerMargin] above the one just rejected is not busy in the
  /// cooldown: it gets its own check (WP126).
  final void Function(
    BargeInKeyword candidate, {
    required bool busy,
    required double score,
  })?
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
  final DevAroundSet _dev;
  bool _verifying = false;
  int _fed = 0, _blockedUntil = 0, _ignoreUntil = 0;
  // End of the last live block with speech level, and the confidence of the
  // candidate whose check ended without a keyword (the cooldown holds it).
  int _lastLoud = -1 << 40;
  double _rejected = 0;
  // Candidate waiting for the end of its word, and the best one that came
  // during a check or the cooldown.
  final _cand = BargeCandidates();
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
    _dev.clear();
    _fed = _blockedUntil = _ignoreUntil = 0;
    _lastLoud = -1 << 40;
    _rejected = 0;
    _cand.clear();
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
    _dev.feed(frame);
    if (verifier != null || _dev.on) _ring.add(frame);
    if (verifier != null) {
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
        _dev.startLast('barge-cand', _ring);
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
      onCandidate?.call(keyword, busy: busy, score: score);
      _dev.startLast('barge-cand', _ring);
      if (busy) {
        _cand.defer(keyword, score, _fed, _lastLoud);
      } else {
        // Waiting (or already waiting): the check starts after the word.
        _cand.addPending(keyword, score, _fed + durationToSamples(settle));
      }
    }
    final v = verifier;
    _cand.follow(_fed, _lastLoud, durationToSamples(settle));
    // A candidate from the cooldown (after a check): once the cooldown is
    // over it is checked, if its word is still inside the clip.
    if (v != null && !_verifying && _fed >= _blockedUntil) {
      _cand.promoteAfterCooldown(
        _fed,
        durationToSamples(clip),
        durationToSamples(settle),
      );
    }
    if (v != null &&
        _cand.pendingAt >= 0 &&
        _fed >= _cand.pendingAt &&
        !_verifying) {
      final kind = _cand.takePending();
      unawaited(_verify(v, kind, gen));
    }
  }

  Future<void> _verify(BargeVerifier v, BargeInKeyword cand, int gen) async {
    final pcm = clipEndingAtSpeech(
      _ring.snapshot(),
      fed: _fed,
      lastLoud: _cand.checkedLoud >= 0 ? _cand.checkedLoud : _lastLoud,
      settle: settle,
      clip: clip,
    );
    if (speechEnd(pcm, minLevel) == 0) {
      // Nothing to recognize (background similarity): no recognizer run.
      onVerdict?.call(const BargeVerdict('skip', null, 'silent'), 0);
      return;
    }
    _dev.emitMarked('barge-verify', pcm, 'speechEnd', speechEnd(pcm, minLevel));
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
      _rejected = _cand.checkedScore;
      // A candidate that came meanwhile is checked once the cooldown ends, a
      // clearly stronger one (the real word after an echo) right after its
      // own settle time; it is lost only when its word left the ring.
      final kept = _cand.rescheduleAfterReject(
        fed: _fed,
        blockedUntil: _blockedUntil,
        settle: durationToSamples(settle),
        ring: durationToSamples(clip + clip),
        margin: strongerMargin,
      );
      if (!kept) {
        onVerdict?.call(const BargeVerdict('skip', null, 'stale'), 0);
      }
      return;
    }
    _cand.deferredKind = null;
    _cand.deferredScore = 0;
    _signals.add(BargeInSignal.keyword(keyword));
  }

  @override
  Future<void> stop() => _serial(() async {
    if (!_running) return;
    _running = false;
    _generation++;
    _dev.flush();
    if (_cand.pendingKind != null) {
      onVerdict?.call(const BargeVerdict('skip', null, 'stopped'), 0);
    }
    _cand.clear();
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
    _dev.flush();
    // Pending candidates and checks are void: nobody speaks to an answer
    // that is over, and the engine gets no more frames.
    _generation++;
    _cand.clear();
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
