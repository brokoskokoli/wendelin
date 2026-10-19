import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One enrolled person: the voice embeddings of the enrollment sentences
/// and the calibrated threshold (WP92a). Embeddings are biometric data: the
/// store keeps them encrypted, they never reach logs, audit or exports. The
/// recordings themselves are not kept.
@immutable
final class SpeakerProfile {
  /// Creates a profile. [embeddings] are L2-normalized.
  SpeakerProfile({
    required this.id,
    required this.name,
    required List<Float32List> embeddings,
    required this.threshold,
    required this.createdAt,
  }) : embeddings = List.unmodifiable(embeddings),
       centroid = _centroid(embeddings);

  /// Stable id (for 92b: the person's key).
  final String id;

  /// Name as the person said it.
  final String name;

  /// Normalized embeddings of the enrollment sentences.
  final List<Float32List> embeddings;

  /// Normalized mean of [embeddings].
  final Float32List centroid;

  /// Cosine score from which a voice counts as this person.
  final double threshold;

  /// When the person was enrolled.
  final DateTime createdAt;

  /// JSON for the encrypted store.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'threshold': threshold,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'embeddings': [
      for (final e in embeddings) base64Encode(e.buffer.asUint8List()),
    ],
  };

  /// Reads [toJson]; `null` if [json] is malformed.
  static SpeakerProfile? fromJson(Object? json) {
    try {
      if (json is! Map<String, Object?>) return null;
      final raw = json['embeddings'];
      if (raw is! List || raw.isEmpty) return null;
      final embs = <Float32List>[];
      for (final r in raw) {
        final bytes = base64Decode(r! as String);
        if (bytes.isEmpty || bytes.length % 4 != 0) return null;
        embs.add(Float32List.fromList(bytes.buffer.asFloat32List()));
      }
      final dim = embs.first.length;
      if (embs.any((e) => e.length != dim)) return null;
      final threshold = (json['threshold']! as num).toDouble();
      final id = json['id']! as String;
      final name = json['name']! as String;
      if (id.isEmpty || !threshold.isFinite) return null;
      return SpeakerProfile(
        id: id,
        name: name,
        embeddings: embs,
        threshold: threshold,
        createdAt: DateTime.parse(json['createdAt']! as String),
      );
    } on Object {
      return null;
    }
  }

  static Float32List _centroid(List<Float32List> embeddings) =>
      normalized(meanOf(embeddings));

  @override
  String toString() => 'SpeakerProfile($id, ${embeddings.length} samples)';
}

/// Mean of equally long [vectors].
Float32List meanOf(List<Float32List> vectors) {
  final out = Float32List(vectors.first.length);
  for (final v in vectors) {
    for (var i = 0; i < out.length; i++) {
      out[i] += v[i] / vectors.length;
    }
  }
  return out;
}

/// [v] scaled to length 1 (the zero vector stays zero).
Float32List normalized(Float32List v) {
  var sum = 0.0;
  for (final x in v) {
    sum += x * x;
  }
  final n = math.sqrt(sum);
  if (n == 0) return Float32List.fromList(v);
  return Float32List.fromList([for (final x in v) x / n]);
}

/// Cosine similarity of two equally long vectors (0 for a zero vector).
double cosine(Float32List a, Float32List b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
