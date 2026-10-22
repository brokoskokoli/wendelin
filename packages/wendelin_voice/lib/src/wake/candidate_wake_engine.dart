import 'dart:typed_data';

import 'keyword_spec.dart';
import 'speech_gate.dart';
import 'wake_feature_extractor.dart';
import 'wake_math.dart';
import 'wake_templates.dart';
import 'wake_word_engine.dart';

/// Stage 1 of the two-stage detection (WP44 Nachtrag 2): a candidate arises
/// when the classifier is above a **low** threshold or a window is similar
/// to a personal template. Stage 2 (transcription) confirms.
final class CandidateWakeEngine implements WarmableWakeEngine {
  /// Creates the engine. [templates] may be `null` (classifier only);
  /// templates of another [WakeFeatureExtractor.featureVersion] are ignored.
  /// [modelThreshold] `null` disables the classifier rule. [refractory]
  /// suppresses further candidates after one.
  CandidateWakeEngine({
    required this.features,
    this.templates,
    this.moreTemplates = const [],
    this.modelThreshold = 0.5,
    this.refractory = const Duration(milliseconds: 1500),
    this.keywordId = 'wake',
    this.stopTemplates = const [],
    this.stopKeywordId = 'stop',
    this.stopTailShare,
    this.stopGate,
    this.stopFloorGap = 0,
    this.stopOverridesWake = false,
    this.onWindow,
    this.mainGate,
    this.directThreshold,
    this.holdWindows = 0,
  });

  /// The feature chain.
  final WakeFeatureExtractor features;

  /// Personal templates.
  final WakeTemplates? templates;

  /// Templates of further speakers (WP50: all learned voices); each set
  /// keeps its own threshold.
  final List<WakeTemplates> moreTemplates;

  /// Low classifier threshold (rule a).
  final double? modelThreshold;

  /// Pause after a candidate.
  final Duration refractory;

  /// Id of the reported keyword.
  final String keywordId;

  /// Templates of the second keyword „Stopp“ (WP64b), all learned voices,
  /// each with its own threshold. Template rule only (no classifier); they
  /// use the same feature windows as the main keyword, so one chain serves
  /// both.
  final List<WakeTemplates> stopTemplates;

  /// Id reported for a „Stopp“ hit.
  final String stopKeywordId;

  /// WP80: share (0..1] of the window, counted from its end, that decides the
  /// „Stopp“ similarity. A window spans about 1.3 s, the word only a quarter
  /// of it; the rest is background whose embeddings look alike in every
  /// recording, so the full-window cosine sits at 0.9 even in silence. The
  /// tail holds the word and its trailing sound. `null`: whole window.
  final double? stopTailShare;

  /// WP80: a „Stopp“ hit needs speech-level sound in the stream (see
  /// [SpeechGate]); `null`: no level check.
  final SpeechGate? stopGate;

  /// WP80: a „Stopp“ hit must also be at least this far above the sliding
  /// background similarity (the stop similarity of the recent windows,
  /// silence or echo). `0`: no check. Applies after a warm-up of
  /// [stopFloorWarmup] windows.
  final double stopFloorGap;

  /// WP113: with stage 2 (the transcript decides) a main-word candidate in a
  /// window where „Stopp“ is also over its raw threshold becomes „Stopp“,
  /// past the level and background gate. Without stage 2 the gate stays
  /// as it is (WP80): „Wendelin“ must not turn into „Stopp“.
  final bool stopOverridesWake;

  /// WP129 (WP126 Folgepunkt b): the main word counts only with speech-level
  /// sound in the stream, whichever rule (classifier or template) fired.
  /// Silence embeddings look like the templates (similarity 0.82..0.83 over
  /// the threshold 0.75), so a silent stream after a warm start would
  /// otherwise be a candidate. `null`: no level check.
  final SpeechGate? mainGate;

  /// WP129: a classifier score at or above this value is a sure hit
  /// (`WakeWordHit.direct`, no stage 2). `null`: every hit goes to stage 2.
  final double? directThreshold;

  /// WP129: from the first window in the band (at or above [modelThreshold],
  /// below [directThreshold]) the classifier score is held for up to this many
  /// windows and the event is decided with its **peak**: when the score falls
  /// below the peak, or at the limit. A score at or above [directThreshold]
  /// decides at once. `0` (or no [directThreshold]): the first window decides.
  final int holdWindows;

  /// Windows before the background similarity is trusted.
  static const stopFloorWarmup = 10;

  /// Sliding background similarity of „Stopp“ (`null` before the first
  /// window), for diagnostics.
  double? get stopFloor => _stopFloor;

  /// Diagnostics (WP72): called for every window with the best similarity to
  /// the main and to the „Stopp“ templates (`-1` without templates) and the
  /// classifier score.
  final void Function(double main, double stop, double? model)? onWindow;

  /// Consecutive windows over the „Stopp“ threshold needed for a hit.
  static const stopWindows = 2;

  bool _open = false;
  int _stopRun = 0;
  int _sinceStop = 1 << 30;
  CandidateDecision? _lastStop;
  double? _stopFloor;
  int _stopSeen = 0;
  int _lastHit = -1 << 40;

  /// Largest classifier score and template similarity seen so far
  /// (diagnostics, e.g. for calibration screens).
  double maxModelScore = 0, maxSimilarity = -1;

  @override
  Future<void> open(List<KeywordSpec> keywords) async {
    if (_open) throw StateError('Engine bereits offen');
    if (!keywords.any((k) => k.id == keywordId)) {
      throw ArgumentError('Schlüsselwort $keywordId fehlt');
    }
    await features.open();
    _open = true;
  }

  @override
  Future<List<WakeWordHit>> accept(Int16List frame) async {
    if (!_open) throw StateError('Engine nicht offen');
    final usable = _usable(
      templates == null ? moreTemplates : [templates!, ...moreTemplates],
    );
    final stops = _usable(stopTemplates);
    final hits = <WakeWordHit>[];
    stopGate?.feed(frame);
    if (mainGate != null && !identical(mainGate, stopGate)) {
      mainGate!.feed(frame);
    }
    for (final w in await features.accept(frame)) {
      if (w.modelScore != null && w.modelScore! > maxModelScore) {
        maxModelScore = w.modelScore!;
      }
      // The speaker whose similarity is closest above the own threshold
      // decides (no speaker: only the classifier rule).
      final score = _eventScore(w.modelScore);
      final main = _closest(w.embedding, usable);
      if (main.top > maxSimilarity) maxSimilarity = main.top;
      var d = decideCandidate(
        modelScore: score,
        templateSimilarity: main.similarity,
        modelThreshold: modelThreshold,
        templateThreshold: main.threshold,
      );
      if (d != null && mainGate != null && !mainGate!.active) d = null;
      final onStop = _mergeStop(w, d, stops, main.top);
      d = onStop.d;
      final id = onStop.id;
      final gap = (refractory.inMicroseconds * 16000) ~/ 1000000;
      if (d == null || w.endSample - _lastHit < gap) continue;
      _lastHit = w.endSample;
      hits.add(
        WakeWordHit(
          keywordId: id,
          endSample: w.endSample,
          confidence: d.confidence,
          reason: d.reason.name,
          score: id == keywordId ? score : null,
          direct:
              id == keywordId &&
              d.reason != CandidateReason.template &&
              directThreshold != null &&
              (score ?? 0) >= directThreshold!,
        ),
      );
    }
    return hits;
  }

  double? _peak;
  int _heldCount = 0;

  /// The score the rules see: the raw one, or with [holdWindows] the peak of
  /// the event once it is decided (`null` while the event is still held).
  double? _eventScore(double? score) {
    final lower = modelThreshold, upper = directThreshold;
    if (holdWindows <= 0 || lower == null || upper == null) return score;
    final peak = _peak;
    if (peak == null) {
      if (score == null || score < lower || score >= upper) return score;
      _peak = score;
      _heldCount = 1;
      return _heldCount >= holdWindows ? _release() : null;
    }
    if (score != null && score >= upper) {
      _peak = null;
      return score;
    }
    if (score != null && score >= peak) {
      _peak = score;
      _heldCount++;
      return _heldCount >= holdWindows ? _release() : null;
    }
    return _release();
  }

  double _release() {
    final peak = _peak!;
    _peak = null;
    return peak;
  }

  /// Merges the main decision [d] with the „Stopp“ rules (WP80, WP113);
  /// returns the final decision and the keyword id.
  ({CandidateDecision? d, String id}) _mergeStop(
    WakeWindow w,
    CandidateDecision? d,
    List<WakeTemplates> stops,
    double mainTop,
  ) {
    var id = keywordId;
    final stop = _closest(w.embedding, stops, tail: stopTailShare);
    onWindow?.call(mainTop, stop.top, w.modelScore);
    var stopDecision = decideCandidate(
      modelScore: null,
      templateSimilarity: stop.similarity,
      modelThreshold: null,
      templateThreshold: stop.threshold,
    );
    final rawStop = stopDecision;
    stopDecision = _gateStop(stopDecision, stop.top, stops.isNotEmpty);
    // „Stopp“ is short: it counts only after [stopWindows] consecutive
    // windows above its threshold (a single spike is no hit).
    _stopRun = stopDecision == null ? 0 : _stopRun + 1;
    _sinceStop = stopDecision == null ? _sinceStop + 1 : 0;
    if (stopDecision != null) {
      _lastStop = stopDecision;
      // WP113: both words over their threshold (during the output): „Stopp“
      // wins, whatever the margins. Otherwise wait for the confirming
      // window, a „Wendelin“ must not slip through meanwhile.
      if (d != null || _stopRun >= stopWindows) {
        d = stopDecision;
        id = stopKeywordId;
      } else {
        d = null;
      }
    } else if (d != null && _lastStop != null && _sinceStop <= stopWindows) {
      // „Stopp“ was over its threshold a moment ago (a spike), now only
      // „Wendelin“ is: it is the same utterance, „Stopp“ wins.
      d = _lastStop;
      id = stopKeywordId;
    }
    // WP113: a candidate of the main word while „Stopp“ is also over its
    // threshold in this window (only the level or background gate kept it
    // back): it is „Stopp“, the other one is its echo in the template.
    if (d != null && id == keywordId && rawStop != null && stopOverridesWake) {
      d = rawStop;
      id = stopKeywordId;
    }
    return (d: d, id: id);
  }

  List<WakeTemplates> _usable(List<WakeTemplates> sets) => [
    for (final t in sets)
      if (t.isCompatible(features.featureVersion)) t,
  ];

  /// WP80: no „Stopp“ without speech-level sound and without a clear rise
  /// over the background similarity ([top] = best similarity); also tracks
  /// that background.
  CandidateDecision? _gateStop(
    CandidateDecision? decision,
    double top,
    bool hasStops,
  ) {
    final floor = _stopFloor;
    if (decision != null) {
      final quiet = stopGate != null && !stopGate!.active;
      final flat =
          stopFloorGap > 0 &&
          floor != null &&
          _stopSeen >= stopFloorWarmup &&
          top < floor + stopFloorGap;
      if (quiet || flat) decision = null;
    }
    if (hasStops) {
      _stopSeen++;
      _stopFloor = floor == null ? top : floor + (top - floor) * 0.05;
    }
    return decision;
  }

  ({double? similarity, double? threshold, double margin, double top}) _closest(
    Float32List embedding,
    List<WakeTemplates> sets, {
    double? tail,
  }) {
    // Tail of the window (WP80): both sides cut at the same offset.
    final from = tail == null
        ? 0
        : embedding.length - (embedding.length * tail).round();
    final probe = from == 0
        ? embedding
        : Float32List.sublistView(embedding, from);
    double? sim, threshold;
    var margin = double.negativeInfinity, top = -1.0;
    for (final t in sets) {
      final s = bestSimilarity(probe, [
        for (final e in t.embeddings)
          from == 0 ? e : Float32List.sublistView(e, from),
      ]);
      if (s > top) top = s;
      if (s - t.threshold > margin) {
        margin = s - t.threshold;
        sim = s;
        threshold = t.threshold;
      }
    }
    return (similarity: sim, threshold: threshold, margin: margin, top: top);
  }

  @override
  Future<void> warmUp(Int16List frame) async {
    if (!_open) throw StateError('Engine nicht offen');
    // Windows are dropped: the earlier audio only fills the chain.
    await features.accept(frame);
  }

  @override
  void reset() {
    features.reset();
    _stopRun = 0;
    _sinceStop = 1 << 30;
    _lastStop = null;
    stopGate?.reset();
    mainGate?.reset();
    _stopFloor = null;
    _stopSeen = 0;
    _lastHit = -1 << 40;
    _peak = null;
    _heldCount = 0;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await features.close();
  }
}
