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
    this.sequences = const [],
  });

  /// Word tag of „Wendelin“ in [WakeTemplateSequence.word].
  static const wordW = 'w';

  /// Word tag of „Hey Wendelin“ in [WakeTemplateSequence.word].
  static const wordHw = 'hw';

  /// Reads [toJson] output.
  factory WakeTemplates.fromJson(Map<String, Object?> json) => WakeTemplates(
    speakerId: json['speakerId']! as String,
    featureVersion: json['featureVersion']! as String,
    threshold: (json['threshold']! as num).toDouble(),
    // Absent in templates before WP134 (raw cosine): they stay unusable.
    center: json['center'] as String?,
    // Absent in templates before WP143: verifier B stays inactive for them.
    sequences: [
      for (final e in (json['sequences'] as List<Object?>?) ?? const [])
        WakeTemplateSequence.fromJson(e! as Map<String, Object?>),
    ],
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

  /// Embedding sequences for verifier B (WP143), one per accepted recording
  /// and word. Empty for templates recorded before: B is inactive for them
  /// and the stage falls back to the recognizer (learn again to enable B).
  final List<WakeTemplateSequence> sequences;

  /// Whether verifier B can use these templates.
  bool get hasSequences => sequences.isNotEmpty;

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
    sequences: sequences,
  );

  /// JSON map (embeddings as base64 of little-endian float32).
  Map<String, Object?> toJson() => {
    'speakerId': speakerId,
    'featureVersion': featureVersion,
    'threshold': threshold,
    'center': ?center,
    if (sequences.isNotEmpty)
      'sequences': [for (final q in sequences) q.toJson()],
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

/// Embedding sequence of one recording for verifier B (WP143): `frames` × 96
/// raw embedding values (not centered; `mu` is applied when comparing).
/// Only embeddings, never audio.
@immutable
final class WakeTemplateSequence {
  /// Creates a sequence of [word] (`WakeTemplates.wordW`, `wordHw`).
  const WakeTemplateSequence({required this.word, required this.values});

  /// Reads [toJson] output.
  factory WakeTemplateSequence.fromJson(Map<String, Object?> json) {
    final bytes = Uint8List.fromList(base64Decode(json['data']! as String));
    return WakeTemplateSequence(
      word: json['word']! as String,
      values: bytes.buffer.asFloat32List(0, bytes.length ~/ 4),
    );
  }

  /// Which wake word was spoken.
  final String word;

  /// The frames, flattened (length is a multiple of 96).
  final Float32List values;

  /// Number of frames.
  int get frames => values.length ~/ 96;

  /// JSON map (values as base64 of little-endian float32).
  Map<String, Object?> toJson() => {
    'word': word,
    'data': base64Encode(Uint8List.view(Float32List.fromList(values).buffer)),
  };
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
