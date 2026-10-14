import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// Minimal binding of the ONNX Runtime C API (WP60). The sherpa-onnx plugin
// ships `libonnxruntime.so` anyway (and offers no generic session in its
// Dart API), so the wake word feature chain (mel spectrogram, embedding)
// runs on that library without a second native dependency (ADR 0008).

/// Version of the C API requested from the library (ORT 1.17; the table
/// layout of older entries never changes, a newer library serves it).
const _ortApiVersion = 17;

// Entry positions in `OrtApi` (onnxruntime_c_api.h; append-only table).
const _getErrorMessage = 2;
const _createEnv = 3;
const _createSession = 7;
const _run = 9;
const _createSessionOptions = 10;
const _setIntraOpNumThreads = 24;
const _createTensorWithData = 49;
const _getTensorMutableData = 51;
const _getDimensionsCount = 61;
const _getDimensions = 62;
const _getTensorTypeAndShape = 65;
const _createCpuMemoryInfo = 69;
const _releaseEnv = 92;
const _releaseStatus = 93;
const _releaseMemoryInfo = 94;
const _releaseSession = 95;
const _releaseValue = 96;
const _releaseTensorInfo = 99;
const _releaseSessionOptions = 100;

typedef _Status = Pointer<Void>;
typedef _PP = Pointer<Pointer<Void>>;

// Native signatures and their Dart counterparts (entries of the table).
typedef _ErrMsgN = Pointer<Utf8> Function(Pointer<Void>);
typedef _ErrMsgD = Pointer<Utf8> Function(Pointer<Void>);
typedef _CreateEnvN = _Status Function(Int32, Pointer<Utf8>, _PP);
typedef _CreateEnvD = _Status Function(int, Pointer<Utf8>, _PP);
typedef _CreateSessionN = _Status Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
  _PP,
);
typedef _CreateSessionD = _Status Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Void>,
  _PP,
);
typedef _RunN = _Status Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<Utf8>>,
  _PP,
  IntPtr,
  Pointer<Pointer<Utf8>>,
  IntPtr,
  _PP,
);
typedef _RunD = _Status Function(
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Pointer<Utf8>>,
  _PP,
  int,
  Pointer<Pointer<Utf8>>,
  int,
  _PP,
);
typedef _OutN = _Status Function(_PP);
typedef _OutD = _Status Function(_PP);
typedef _ThreadsN = _Status Function(Pointer<Void>, Int32);
typedef _ThreadsD = _Status Function(Pointer<Void>, int);
typedef _TensorN = _Status Function(
  Pointer<Void>,
  Pointer<Void>,
  IntPtr,
  Pointer<Int64>,
  IntPtr,
  Int32,
  _PP,
);
typedef _TensorD = _Status Function(
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<Int64>,
  int,
  int,
  _PP,
);
typedef _PtrOutN = _Status Function(Pointer<Void>, _PP);
typedef _PtrOutD = _Status Function(Pointer<Void>, _PP);
typedef _CountN = _Status Function(Pointer<Void>, Pointer<IntPtr>);
typedef _CountD = _Status Function(Pointer<Void>, Pointer<IntPtr>);
typedef _DimsN = _Status Function(Pointer<Void>, Pointer<Int64>, IntPtr);
typedef _DimsD = _Status Function(Pointer<Void>, Pointer<Int64>, int);
typedef _MemN = _Status Function(Int32, Int32, _PP);
typedef _MemD = _Status Function(int, int, _PP);
typedef _ReleaseN = Void Function(Pointer<Void>);
typedef _ReleaseD = void Function(Pointer<Void>);

/// Failure reported by the ONNX Runtime.
final class OrtException implements Exception {
  /// Creates the exception.
  const OrtException(this.message);

  /// The runtime's message.
  final String message;

  @override
  String toString() => 'OrtException: $message';
}

/// One output tensor (float32) of a run.
final class OrtTensor {
  /// Creates a tensor.
  const OrtTensor(this.data, this.shape);

  /// Values (row-major).
  final Float32List data;

  /// Dimensions.
  final List<int> shape;
}

/// The loaded runtime: environment and the API table.
final class OrtRuntime {
  OrtRuntime._(_Pointers api) : _a = api;

  /// Loads the runtime from [library] (default `libonnxruntime.so`, which
  /// the sherpa-onnx plugin puts into the APK).
  factory OrtRuntime.open([DynamicLibrary? library]) {
    final lib = library ?? DynamicLibrary.open('libonnxruntime.so');
    final base = lib.lookupFunction<_PP Function(), _PP Function()>(
      'OrtGetApiBase',
    )();
    final getApi = base[0]
        .cast<NativeFunction<_PP Function(Uint32)>>()
        .asFunction<_PP Function(int)>();
    final table = getApi(_ortApiVersion);
    if (table == nullptr) {
      throw const OrtException('API-Version nicht verfügbar');
    }
    final rt = OrtRuntime._(_Pointers(table));
    final env = calloc<Pointer<Void>>();
    final name = 'wendelin'.toNativeUtf8();
    try {
      rt._check(rt._a.createEnv(3, name, env));
      rt._env = env.value;
      return rt;
    } finally {
      calloc.free(env);
      malloc.free(name);
    }
  }

  final _Pointers _a;
  Pointer<Void> _env = nullptr;

  void _check(_Status status) {
    if (status == nullptr) return;
    final msg = _a.errorMessage(status).toDartString();
    _a.releaseStatus(status);
    throw OrtException(msg);
  }

  /// Opens the model file at [path] on one thread.
  OrtSession open(String path) {
    final opts = calloc<Pointer<Void>>();
    final out = calloc<Pointer<Void>>();
    final cpath = path.toNativeUtf8();
    try {
      _check(_a.createSessionOptions(opts));
      _check(_a.setIntraOpNumThreads(opts.value, 1));
      _check(_a.createSession(_env, cpath, opts.value, out));
      return OrtSession._(this, out.value);
    } finally {
      if (opts.value != nullptr) _a.releaseSessionOptions(opts.value);
      calloc.free(opts);
      calloc.free(out);
      malloc.free(cpath);
    }
  }

  /// Frees the environment (open sessions first).
  void close() {
    if (_env != nullptr) _a.releaseEnv(_env);
    _env = nullptr;
  }
}

/// The used entries of the API table, resolved once.
final class _Pointers {
  _Pointers(this.table);

  final _PP table;

  Pointer<NativeFunction<T>> _at<T extends Function>(int i) =>
      table[i].cast<NativeFunction<T>>();

  late final errorMessage = _at<_ErrMsgN>(_getErrorMessage)
      .asFunction<_ErrMsgD>();
  late final createEnv = _at<_CreateEnvN>(_createEnv).asFunction<_CreateEnvD>();
  late final createSession = _at<_CreateSessionN>(_createSession)
      .asFunction<_CreateSessionD>();
  late final run = _at<_RunN>(_run).asFunction<_RunD>();
  late final createSessionOptions = _at<_OutN>(_createSessionOptions)
      .asFunction<_OutD>();
  late final setIntraOpNumThreads = _at<_ThreadsN>(_setIntraOpNumThreads)
      .asFunction<_ThreadsD>();
  late final createTensor = _at<_TensorN>(_createTensorWithData)
      .asFunction<_TensorD>();
  late final tensorData = _at<_PtrOutN>(_getTensorMutableData)
      .asFunction<_PtrOutD>();
  late final dimsCount = _at<_CountN>(_getDimensionsCount)
      .asFunction<_CountD>();
  late final dims = _at<_DimsN>(_getDimensions).asFunction<_DimsD>();
  late final typeAndShape = _at<_PtrOutN>(_getTensorTypeAndShape)
      .asFunction<_PtrOutD>();
  late final cpuMemory = _at<_MemN>(_createCpuMemoryInfo).asFunction<_MemD>();
  late final releaseEnv = _at<_ReleaseN>(_releaseEnv).asFunction<_ReleaseD>();
  late final releaseStatus = _at<_ReleaseN>(_releaseStatus)
      .asFunction<_ReleaseD>();
  late final releaseMemory = _at<_ReleaseN>(_releaseMemoryInfo)
      .asFunction<_ReleaseD>();
  late final releaseSession = _at<_ReleaseN>(_releaseSession)
      .asFunction<_ReleaseD>();
  late final releaseValue = _at<_ReleaseN>(_releaseValue)
      .asFunction<_ReleaseD>();
  late final releaseTensorInfo = _at<_ReleaseN>(_releaseTensorInfo)
      .asFunction<_ReleaseD>();
  late final releaseSessionOptions = _at<_ReleaseN>(_releaseSessionOptions)
      .asFunction<_ReleaseD>();
}

/// One loaded model with a single float32 input and output.
final class OrtSession {
  OrtSession._(this._rt, this._handle);

  final OrtRuntime _rt;
  Pointer<Void> _handle;

  /// Runs the model: [input] (named [inputName], shape [shape]) to the
  /// output [outputName].
  OrtTensor run(
    String inputName,
    Float32List input,
    List<int> shape,
    String outputName,
  ) {
    if (_handle == nullptr) throw StateError('Sitzung geschlossen');
    final a = _rt._a;
    final mem = calloc<Pointer<Void>>();
    final value = calloc<Pointer<Void>>();
    final result = calloc<Pointer<Void>>();
    final data = calloc<Float>(input.length);
    final dims = calloc<Int64>(shape.length);
    final inNames = calloc<Pointer<Utf8>>();
    final outNames = calloc<Pointer<Utf8>>();
    inNames[0] = inputName.toNativeUtf8();
    outNames[0] = outputName.toNativeUtf8();
    data.asTypedList(input.length).setAll(0, input);
    for (var i = 0; i < shape.length; i++) {
      dims[i] = shape[i];
    }
    try {
      _rt._check(a.cpuMemory(1, 0, mem)); // arena allocator, default memory
      _rt._check(
        a.createTensor(
          mem.value,
          data.cast(),
          input.length * 4,
          dims,
          shape.length,
          1, // ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
          value,
        ),
      );
      _rt._check(
        a.run(_handle, nullptr, inNames, value, 1, outNames, 1, result),
      );
      return _read(result.value);
    } finally {
      if (result.value != nullptr) a.releaseValue(result.value);
      if (value.value != nullptr) a.releaseValue(value.value);
      if (mem.value != nullptr) a.releaseMemory(mem.value);
      malloc.free(inNames[0]);
      malloc.free(outNames[0]);
      for (final p in <Pointer<NativeType>>[
        mem,
        value,
        result,
        data,
        dims,
        inNames,
        outNames,
      ]) {
        calloc.free(p);
      }
    }
  }

  OrtTensor _read(Pointer<Void> value) {
    final a = _rt._a;
    final info = calloc<Pointer<Void>>();
    final count = calloc<IntPtr>();
    final ptr = calloc<Pointer<Void>>();
    try {
      _rt._check(a.typeAndShape(value, info));
      _rt._check(a.dimsCount(info.value, count));
      final rank = count.value;
      final dims = calloc<Int64>(rank);
      try {
        _rt._check(a.dims(info.value, dims, rank));
        final shape = [for (var i = 0; i < rank; i++) dims[i]];
        var n = 1;
        for (final d in shape) {
          n *= d;
        }
        _rt._check(a.tensorData(value, ptr));
        return OrtTensor(
          Float32List.fromList(ptr.value.cast<Float>().asTypedList(n)),
          shape,
        );
      } finally {
        calloc.free(dims);
      }
    } finally {
      if (info.value != nullptr) a.releaseTensorInfo(info.value);
      calloc.free(info);
      calloc.free(count);
      calloc.free(ptr);
    }
  }

  /// Frees the model. Idempotent.
  void close() {
    if (_handle == nullptr) return;
    _rt._a.releaseSession(_handle);
    _handle = nullptr;
  }
}
