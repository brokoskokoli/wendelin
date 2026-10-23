import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;
// The Dart wrapper of sherpa-onnx 1.13.8 drops `ys_log_probs` from the
// result JSON; the raw binding still delivers it.
// ignore: implementation_imports
import 'package:sherpa_onnx/src/sherpa_onnx_bindings.dart';

import 'whisper_stt.dart';

/// Mean log probability of the tokens `stream` decoded ([meanLogProbOf]),
/// `null` if the library or model does not report it. Never throws: the
/// value is only logged (WP140).
double? streamMeanLogProb(so.OfflineStream stream) {
  try {
    final read = SherpaOnnxBindings.getOfflineStreamResultAsJson;
    if (read == null || stream.ptr == nullptr) return null;
    final json = read(stream.ptr);
    if (json == nullptr) return null;
    try {
      return meanLogProbOf(json.toDartString());
    } finally {
      SherpaOnnxBindings.destroyOfflineStreamResultJson?.call(json);
    }
  } on Object {
    return null;
  }
}
