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
final class CandidateWakeEngine implements WakeWordEngine {
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
    this.onWindow,
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
    for (final w in await features.accept(frame)) {
      if (w.modelScore != null && w.modelScore! > maxModelScore) {
        maxModelScore = w.modelScore!;
      }
      // The speaker whose similarity is closest above the own threshold
      // decides (no speaker: only the classifier rule).
      final main = _closest(w.embedding, usable);
      if (main.top > maxSimilarity) maxSimilarity = main.top;
      var d = decideCandidate(
        modelScore: w.modelScore,
        templateSimilarity: main.similarity,
        modelThreshold: modelThreshold,
        templateThreshold: main.threshold,
      );
      var id = keywordId;
      final stop = _closest(w.embedding, stops, tail: stopTailShare);
      onWindow?.call(main.top, stop.top, w.modelScore);
      var stopDecision = decideCandidate(
        modelScore: null,
        templateSimilarity: stop.similarity,
        modelThreshold: null,
        templateThreshold: stop.threshold,
      );
      // WP80: no „Stopp“ without speech-level sound and without a clear rise
      // over the background similarity.
      final floor = _stopFloor;
      if (stopDecision != null) {
        final quiet = stopGate != null && !stopGate!.active;
        final flat =
            stopFloorGap > 0 &&
            floor != null &&
            _stopSeen >= stopFloorWarmup &&
            stop.top < floor + stopFloorGap;
        if (quiet || flat) stopDecision = null;
      }
      if (stops.isNotEmpty) {
        _stopSeen++;
        _stopFloor = floor == null
            ? stop.top
            : floor + (stop.top - floor) * 0.05;
      }
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
      final gap = (refractory.inMicroseconds * 16000) ~/ 1000000;
      if (d == null || w.endSample - _lastHit < gap) continue;
      _lastHit = w.endSample;
      hits.add(
        WakeWordHit(
          keywordId: id,
          endSample: w.endSample,
          confidence: d.confidence,
          reason: d.reason.name,
        ),
      );
    }
    return hits;
  }

  List<WakeTemplates> _usable(List<WakeTemplates> sets) => [
    for (final t in sets)
      if (t.isCompatible(features.featureVersion)) t,
  ];

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
  void reset() {
    features.reset();
    _stopRun = 0;
    _sinceStop = 1 << 30;
    _lastStop = null;
    stopGate?.reset();
    _stopFloor = null;
    _stopSeen = 0;
    _lastHit = -1 << 40;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await features.close();
  }
}
