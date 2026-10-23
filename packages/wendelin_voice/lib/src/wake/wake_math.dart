import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Cosine similarity of [a] and [b] (same length), 0 when one is zero.
double cosineSimilarity(Float32List a, Float32List b) {
  if (a.length != b.length) {
    throw ArgumentError('Längen verschieden: ${a.length} != ${b.length}');
  }
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Cosine similarity of `a - mean` and `b - mean` (WP134): the embeddings
/// share a large fixed component (about 71 % of the energy), so raw cosines
/// of unrelated audio, noise and digital silence all lie near 0.85. Without
/// it the spread between speech and background is 0.1..0.4 instead of 0.02.
/// 0 when one centered vector is zero.
double centeredCosine(Float32List a, Float32List b, Float32List mean) {
  if (a.length != b.length || a.length != mean.length) {
    throw ArgumentError(
      'Längen verschieden: ${a.length}, ${b.length}, ${mean.length}',
    );
  }
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    final x = a[i] - mean[i], y = b[i] - mean[i];
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

/// Highest similarity of [embedding] to any of [templates]; `-1` when there
/// are none. With [mean] (the extractor's `embeddingMean`) the cosine is
/// centered, see [centeredCosine]; `null` compares the raw vectors.
double bestSimilarity(
  Float32List embedding,
  List<Float32List> templates, {
  Float32List? mean,
}) {
  var best = -1.0;
  for (final t in templates) {
    final s = mean == null
        ? cosineSimilarity(embedding, t)
        : centeredCosine(embedding, t, mean);
    if (s > best) best = s;
  }
  return best;
}

/// Which stage-1 rule made a candidate.
enum CandidateReason {
  /// The WP58 classifier is above its (low) threshold.
  model,

  /// A personal template is similar enough.
  template,

  /// Both.
  both,
}

/// Outcome of the stage-1 rule.
@immutable
final class CandidateDecision {
  /// Creates a decision.
  const CandidateDecision(this.reason, this.confidence);

  /// Why it is a candidate.
  final CandidateReason reason;

  /// 0..1: the larger margin above a threshold, scaled.
  final double confidence;
}

/// Stage-1 rule: a candidate exists when the classifier score is at least
/// [modelThreshold] (a) **or** the best template similarity is at least
/// [templateThreshold] (b). Pass `null` for an unavailable source (no
/// classifier / no templates); `null` thresholds disable that rule.
CandidateDecision? decideCandidate({
  required double? modelScore,
  required double? templateSimilarity,
  required double? modelThreshold,
  required double? templateThreshold,
}) {
  final m =
      modelScore != null &&
      modelThreshold != null &&
      modelScore >= modelThreshold;
  final t =
      templateSimilarity != null &&
      templateThreshold != null &&
      templateSimilarity >= templateThreshold;
  if (!m && !t) return null;
  final conf = math.max(m ? modelScore : 0.0, t ? templateSimilarity : 0.0);
  return CandidateDecision(
    m && t
        ? CandidateReason.both
        : m
        ? CandidateReason.model
        : CandidateReason.template,
    conf.clamp(0.0, 1.0),
  );
}
