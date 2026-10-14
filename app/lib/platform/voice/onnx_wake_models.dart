import 'dart:typed_data';

import 'ort_session.dart';
import 'wake_feature_chain.dart';

/// The openWakeWord models (`melspectrogram.onnx`, `embedding_model.onnx`,
/// catalog entry `wake-features`) on the ONNX Runtime of sherpa-onnx.
final class OnnxWakeModels implements WakeModelRunner {
  OnnxWakeModels._(this._runtime, this._mel, this._embedding);

  /// Opens both models from [directory].
  factory OnnxWakeModels.open(String directory, {OrtRuntime? runtime}) {
    final rt = runtime ?? OrtRuntime.open();
    OrtSession? mel;
    try {
      mel = rt.open('$directory/melspectrogram.onnx');
      return OnnxWakeModels._(
        rt,
        mel,
        rt.open('$directory/embedding_model.onnx'),
      );
    } on Object {
      mel?.close();
      if (runtime == null) rt.close();
      rethrow;
    }
  }

  final OrtRuntime _runtime;
  final OrtSession _mel;
  final OrtSession _embedding;

  @override
  Float32List mel(Float32List samples) =>
      _mel.run('input', samples, [1, samples.length], 'output').data;

  @override
  Float32List embed(Float32List frames) => _embedding.run('input_1', frames, [
    1,
    WakeFeatureChain.melFrames,
    32,
    1,
  ], 'conv2d_19').data;

  @override
  void close() {
    _mel.close();
    _embedding.close();
    _runtime.close();
  }
}
