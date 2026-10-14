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

  /// Loads the models.
  Future<void> open();

  /// Feeds one frame and returns the windows that became available.
  Future<List<WakeWindow>> accept(Int16List frame);

  /// Starts a new stream (clears the internal buffers).
  void reset();

  /// Releases the models. Idempotent.
  Future<void> close();
}
