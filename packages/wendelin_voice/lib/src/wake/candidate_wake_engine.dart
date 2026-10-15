import 'dart:typed_data';

import 'keyword_spec.dart';
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

  bool _open = false;
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
      final stop = _closest(w.embedding, stops);
      final stopDecision = decideCandidate(
        modelScore: null,
        templateSimilarity: stop.similarity,
        modelThreshold: null,
        templateThreshold: stop.threshold,
      );
      // Both words match: the one further above its threshold wins.
      if (stopDecision != null && (d == null || stop.margin > main.margin)) {
        d = stopDecision;
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
    List<WakeTemplates> sets,
  ) {
    double? sim, threshold;
    var margin = double.negativeInfinity, top = -1.0;
    for (final t in sets) {
      final s = bestSimilarity(embedding, t.embeddings);
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
    _lastHit = -1 << 40;
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await features.close();
  }
}
