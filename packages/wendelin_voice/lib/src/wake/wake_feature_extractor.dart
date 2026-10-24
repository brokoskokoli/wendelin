import 'dart:typed_data';

import 'package:meta/meta.dart';

/// One classifier window of the openWakeWord feature chain: 16 embeddings of
/// 96 values (1 536), one new window every 80 ms.
@immutable
final class WakeWindow {
  /// Creates a window.
  const WakeWindow({
    required this.endSample,
    required this.embedding,
    this.modelScore,
  });

  /// Stream position (samples) at which the window became available.
  final int endSample;

  /// The flattened window.
  final Float32List embedding;

  /// Output of the WP58 classifier (0..1); `null` without the classifier.
  final double? modelScore;
}

/// openWakeWord feature chain (mel spectrogram and embedding ONNX models,
/// optionally the WP58 classifier) behind a port. The app runs the models
/// on the onnxruntime that ships with sherpa-onnx.
abstract interface class WakeFeatureExtractor {
  /// Identifies the feature models; stored with the personal templates.
  String get featureVersion;

  /// Fixed mean of the embedding windows (WP134): template and window are
  /// centered with it before the cosine. `null`: raw vectors (fakes).
  Float32List? get embeddingMean;

  /// Identifies [embeddingMean]; stored with the templates (they are
  /// unusable with another value). `null` when there is no mean.
  String? get centerId;

  /// Loads the models.
  Future<void> open();

  /// Feeds one frame and returns the windows that became available.
  Future<List<WakeWindow>> accept(Int16List frame);

  /// Starts a new stream (clears the internal buffers).
  void reset();

  /// Releases the models. Idempotent.
  Future<void> close();
}

/// A [WakeFeatureExtractor] that can also embed a whole clip at once, like
/// openWakeWord's batch call (verifier B, WP143): the mel spectrogram of the
/// clip (cut to a multiple of 160 samples, `k - 3` frames for `k` blocks of
/// 160), one embedding per 76 mel frames with a stride of 8. The streaming
/// chain starts its embeddings in another phase, so it cannot stand in.
abstract interface class WakeSequenceExtractor implements WakeFeatureExtractor {
  /// Embedding frames of [clip] (`frames` x 96, flattened), or `null` when
  /// the clip yields fewer than 76 mel frames (too short). The extractor
  /// must be open.
  Future<Float32List?> sequence(Int16List clip);
}
