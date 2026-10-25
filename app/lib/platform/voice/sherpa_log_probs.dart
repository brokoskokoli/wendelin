import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

import 'whisper_stt.dart';

typedef _GetJsonNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _GetJson = Pointer<Utf8> Function(Pointer<Void>);
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

/// The Dart wrapper of sherpa-onnx 1.13.8 drops `ys_log_probs` from the
/// result JSON; the C API still delivers it. Own small binding to the
/// already loaded library (dlopen returns the same handle); symbols that
/// are missing mean "no value", never an error.
({_GetJson read, _Free free})? _symbols;
bool _resolved = false;

({_GetJson read, _Free free})? _resolve() {
  if (_resolved) return _symbols;
  _resolved = true;
  try {
    final lib = Platform.isAndroid || Platform.isLinux
        ? DynamicLibrary.open('libsherpa-onnx-c-api.so')
        : DynamicLibrary.process();
    _symbols = (
      read: lib
          .lookup<NativeFunction<_GetJsonNative>>(
            'SherpaOnnxGetOfflineStreamResultAsJson',
          )
          .asFunction<_GetJson>(),
      free: lib
          .lookup<NativeFunction<_FreeNative>>(
            'SherpaOnnxDestroyOfflineStreamResultJson',
          )
          .asFunction<_Free>(),
    );
  } on Object {
    _symbols = null;
  }
  return _symbols;
}

/// Mean and smallest log probability of the tokens `stream` decoded
/// ([logProbsOf]), `null` if the library or model does not report it. Never
/// throws: the values are only logged (WP140, WP146).
({double mean, double min})? streamLogProbs(so.OfflineStream stream) {
  try {
    final sym = _resolve();
    if (sym == null || stream.ptr == nullptr) return null;
    final json = sym.read(stream.ptr.cast<Void>());
    if (json == nullptr) return null;
    try {
      return logProbsOf(json.toDartString());
    } finally {
      sym.free(json);
    }
  } on Object {
    return null;
  }
}
