import 'dart:typed_data';

import 'ort_session.dart';
import 'wake_feature_chain.dart';

/// The openWakeWord models (`melspectrogram.onnx`, `embedding_model.onnx`,
/// catalog entry `wake-features`) on the ONNX Runtime of sherpa-onnx.
final class OnnxWakeModels implements WakeModelRunner, WakeClassifier {
  OnnxWakeModels._(
    this._runtime,
    this._mel,
    this._embedding,
    this._classifier,
    this._optional,
    this._classifyCost,
    this._onClassifierIssue,
  );

  /// Opens both models from [directory]; with [classifierPath] (WP129) also
  /// the trained classifier, so the windows carry a score. Any failure
  /// closes what is open and throws (fail closed).
  ///
  /// WP171 (developer mode, classifier only as a second opinion):
  /// [classifierOptional] keeps the chain alive without the classifier, if it
  /// cannot be opened or fails later; [onClassifierIssue] hears it once. The
  /// windows then carry no score. [classifyCost] gets the time of each score.
  factory OnnxWakeModels.open(
    String directory, {
    OrtRuntime? runtime,
    String? classifierPath,
    bool classifierOptional = false,
    void Function(Duration)? classifyCost,
    void Function(String reason)? onClassifierIssue,
  }) {
    final rt = runtime ?? OrtRuntime.open();
    OrtSession? mel, emb;
    try {
      mel = rt.open('$directory/melspectrogram.onnx');
      emb = rt.open('$directory/embedding_model.onnx');
      OrtSession? classifier;
      if (classifierPath != null) {
        try {
          classifier = rt.open(classifierPath);
        } on Object {
          if (!classifierOptional) rethrow;
          onClassifierIssue?.call('open-failed');
        }
      }
      return OnnxWakeModels._(
        rt,
        mel,
        emb,
        classifier,
        classifierOptional,
        classifyCost,
        onClassifierIssue,
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
  OrtSession? _classifier;
  final bool _optional;
  final void Function(Duration)? _classifyCost;
  final void Function(String)? _onClassifierIssue;

  @override
  bool get hasClassifier => _classifier != null;

  @override
  double classify(Float32List window) {
    final c = _classifier;
    if (c == null) throw StateError('Kein Klassifikator geladen');
    if (window.length != 16 * 96) {
      throw ArgumentError('Fenster hat ${window.length} statt 1536 Werte');
    }
    final clock = Stopwatch()..start();
    try {
      final out = c.run('input', window, [1, 16, 96], 'output').data;
      if (out.isEmpty) throw const OrtException('Klassifikator ohne Ausgabe');
      return out[0];
    } on Object {
      if (!_optional) rethrow;
      // Optional: drop the classifier, the chain goes on without scores.
      _classifier = null;
      c.close();
      _onClassifierIssue?.call('run-failed');
      return double.nan;
    } finally {
      _classifyCost?.call(clock.elapsed);
    }
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
