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
    this.modelThreshold = 0.5,
    this.refractory = const Duration(milliseconds: 1500),
    this.keywordId = 'wake',
  });

  /// The feature chain.
  final WakeFeatureExtractor features;

  /// Personal templates.
  final WakeTemplates? templates;

  /// Low classifier threshold (rule a).
  final double? modelThreshold;

  /// Pause after a candidate.
  final Duration refractory;

  /// Id of the reported keyword.
  final String keywordId;

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
    final t = templates;
    final usable = t != null && t.isCompatible(features.featureVersion)
        ? t
        : null;
    final hits = <WakeWordHit>[];
    for (final w in await features.accept(frame)) {
      final sim = usable == null
          ? null
          : bestSimilarity(w.embedding, usable.embeddings);
      if (w.modelScore != null && w.modelScore! > maxModelScore) {
        maxModelScore = w.modelScore!;
      }
      if (sim != null && sim > maxSimilarity) maxSimilarity = sim;
      final d = decideCandidate(
        modelScore: w.modelScore,
        templateSimilarity: sim,
        modelThreshold: modelThreshold,
        templateThreshold: usable?.threshold,
      );
      final gap = (refractory.inMicroseconds * 16000) ~/ 1000000;
      if (d == null || w.endSample - _lastHit < gap) continue;
      _lastHit = w.endSample;
      hits.add(
        WakeWordHit(
          keywordId: keywordId,
          endSample: w.endSample,
          confidence: d.confidence,
          reason: d.reason.name,
        ),
      );
    }
    return hits;
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
