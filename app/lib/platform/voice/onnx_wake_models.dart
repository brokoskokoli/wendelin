import 'dart:typed_data';

import 'ort_session.dart';
import 'wake_feature_chain.dart';

/// The openWakeWord models (`melspectrogram.onnx`, `embedding_model.onnx`,
/// catalog entry `wake-features`) on the ONNX Runtime of sherpa-onnx.
final class OnnxWakeModels implements WakeModelRunner, WakeClassifier {
  OnnxWakeModels._(this._runtime, this._mel, this._embedding, this._classifier);

  /// Opens both models from [directory]; with [classifierPath] (WP129) also
  /// the trained classifier, so the windows carry a score. Any failure
  /// closes what is open and throws (fail closed).
  factory OnnxWakeModels.open(
    String directory, {
    OrtRuntime? runtime,
    String? classifierPath,
  }) {
    final rt = runtime ?? OrtRuntime.open();
    OrtSession? mel, emb;
    try {
      mel = rt.open('$directory/melspectrogram.onnx');
      emb = rt.open('$directory/embedding_model.onnx');
      return OnnxWakeModels._(
        rt,
        mel,
        emb,
        classifierPath == null ? null : rt.open(classifierPath),
      );
    } on Object {
      mel?.close();
      emb?.close();
      if (runtime == null) rt.close();
      rethrow;
    }
  }

  final OrtRuntime _runtime;
  final OrtSession _mel;
  final OrtSession _embedding;
  final OrtSession? _classifier;

  @override
  bool get hasClassifier => _classifier != null;

  @override
  double classify(Float32List window) {
    final c = _classifier;
    if (c == null) throw StateError('Kein Klassifikator geladen');
    if (window.length != 16 * 96) {
      throw ArgumentError('Fenster hat ${window.length} statt 1536 Werte');
    }
    final out = c.run('input', window, [1, 16, 96], 'output').data;
    if (out.isEmpty) throw const OrtException('Klassifikator ohne Ausgabe');
    return out[0];
  }

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
    _classifier?.close();
    _runtime.close();
  }
}
