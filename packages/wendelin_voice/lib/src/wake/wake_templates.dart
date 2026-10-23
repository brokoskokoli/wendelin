import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Personal wake word templates of one speaker (WP60 records them, WP44
/// matches them). Only embeddings, never raw audio.
@immutable
final class WakeTemplates {
  /// Creates templates.
  const WakeTemplates({
    required this.speakerId,
    required this.featureVersion,
    required this.threshold,
    required this.embeddings,
    this.center,
  });

  /// Reads [toJson] output.
  factory WakeTemplates.fromJson(Map<String, Object?> json) => WakeTemplates(
    speakerId: json['speakerId']! as String,
    featureVersion: json['featureVersion']! as String,
    threshold: (json['threshold']! as num).toDouble(),
    // Absent in templates before WP134 (raw cosine): they stay unusable.
    center: json['center'] as String?,
    embeddings: [
      for (final e in json['embeddings']! as List<Object?>)
        _decode(e! as String),
    ],
  );

  /// Speaker the templates belong to.
  final String speakerId;

  /// Version of the feature models (mel + embedding) that produced them;
  /// templates of another version are unusable.
  final String featureVersion;

  /// Calibrated cosine threshold.
  final double threshold;

  /// One embedding window (flattened) per recorded utterance.
  final List<Float32List> embeddings;

  /// Id of the embedding mean the comparison centers with (WP134); `null`
  /// for templates recorded before: their padding was digital silence and
  /// cannot be removed afterwards, so they must be recorded again.
  final String? center;

  /// Whether the templates fit the feature models [version] and the mean
  /// [center] of the extractor.
  bool isCompatible(String version, {String? center}) =>
      version == featureVersion &&
      center == this.center &&
      embeddings.isNotEmpty;

  /// A copy with a new [threshold] (after re-calibration).
  WakeTemplates withThreshold(double threshold) => WakeTemplates(
    speakerId: speakerId,
    featureVersion: featureVersion,
    threshold: threshold,
    embeddings: embeddings,
    center: center,
  );

  /// JSON map (embeddings as base64 of little-endian float32).
  Map<String, Object?> toJson() => {
    'speakerId': speakerId,
    'featureVersion': featureVersion,
    'threshold': threshold,
    'center': ?center,
    'embeddings': [
      for (final e in embeddings)
        base64Encode(Uint8List.view(Float32List.fromList(e).buffer)),
    ],
  };

  static Float32List _decode(String s) {
    final bytes = base64Decode(s);
    final copy = Uint8List.fromList(bytes);
    return copy.buffer.asFloat32List(0, copy.length ~/ 4);
  }
}

/// Persistence of [WakeTemplates] (port; the app stores them in its private
/// directory). Contract: [load] returns what [save] stored, `null` when
/// nothing is stored; [delete] forgets the speaker.
abstract interface class WakeTemplateStore {
  /// Templates of [speakerId], or `null`.
  Future<WakeTemplates?> load(String speakerId);

  /// Stores (replaces) the templates of `templates.speakerId`.
  Future<void> save(WakeTemplates templates);

  /// Removes the templates of [speakerId].
  Future<void> delete(String speakerId);
}
