import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/ort_session.dart';

// A fake ONNX Runtime API table (native callbacks) counts what the binding
// creates and releases; the real library is only available on the device.

typedef P = Pointer<Void>;
typedef PP = Pointer<Pointer<Void>>;

final counts = <String, int>{};
int elementType = 1;
bool failRun = false;
final _data = calloc<Float>(4);

void _inc(String k) => counts[k] = (counts[k] ?? 0) + 1;

P _handle(PP out, String kind) {
  _inc('create $kind');
  out.value = Pointer.fromAddress(0x1000 + (counts['create $kind'] ?? 0));
  return nullptr;
}

P _createEnv(int level, Pointer<Utf8> name, PP out) => _handle(out, 'env');
P _options(PP out) => _handle(out, 'options');
P _threads(P options, int n) => nullptr;

/// Opening the n-th session fails (1-based, 0 = never).
int failSessionNumber = 0;

P _session(P env, Pointer<Utf8> path, P options, PP out) {
  final n = (counts['create session'] ?? 0) + 1;
  if (n == failSessionNumber) {
    _inc('create session failed');
    return Pointer.fromAddress(0x9999);
  }
  return _handle(out, 'session');
}

P _memory(int a, int b, PP out) => _handle(out, 'memory');
P _tensor(
  P mem,
  P data,
  int bytes,
  Pointer<Int64> dims,
  int rank,
  int type,
  PP out,
) => _handle(out, 'value');
P _run(
  P session,
  P options,
  Pointer<Pointer<Utf8>> inNames,
  PP inputs,
  int inCount,
  Pointer<Pointer<Utf8>> outNames,
  int outCount,
  PP outputs,
) {
  if (failRun) return Pointer.fromAddress(0x9999);
  return _handle(outputs, 'value');
}

P _typeAndShape(P value, PP out) => _handle(out, 'info');
P _elementType(P info, Pointer<Int32> out) {
  out.value = elementType;
  return nullptr;
}

P _dimsCount(P info, Pointer<IntPtr> out) {
  out.value = 2;
  return nullptr;
}

P _dims(P info, Pointer<Int64> out, int rank) {
  out[0] = 1;
  out[1] = 4;
  return nullptr;
}

P _tensorData(P value, PP out) {
  out.value = _data.cast();
  return nullptr;
}

Pointer<Utf8> _errorMessage(P status) => 'kaputt'.toNativeUtf8();

void _releaseOf(String kind) => _inc('release $kind');
void _relEnv(P p) => _releaseOf('env');
void _relStatus(P p) => _releaseOf('status');
void _relMemory(P p) => _releaseOf('memory');
void _relSession(P p) => _releaseOf('session');
void _relValue(P p) => _releaseOf('value');
void _relInfo(P p) => _releaseOf('info');
void _relOptions(P p) => _releaseOf('options');

PP fakeTable() {
  final t = calloc<Pointer<Void>>(128);
  t[2] = Pointer.fromFunction<Pointer<Utf8> Function(P)>(_errorMessage).cast();
  t[3] = Pointer.fromFunction<P Function(Int32, Pointer<Utf8>, PP)>(_createEnv)
      .cast();
  t[7] = Pointer.fromFunction<P Function(P, Pointer<Utf8>, P, PP)>(_session)
      .cast();
  t[9] =
      Pointer.fromFunction<
            P Function(
              P,
              P,
              Pointer<Pointer<Utf8>>,
              PP,
              IntPtr,
              Pointer<Pointer<Utf8>>,
              IntPtr,
              PP,
            )
          >(_run)
          .cast();
  t[10] = Pointer.fromFunction<P Function(PP)>(_options).cast();
  t[24] = Pointer.fromFunction<P Function(P, Int32)>(_threads).cast();
  t[49] =
      Pointer.fromFunction<
            P Function(P, P, IntPtr, Pointer<Int64>, IntPtr, Int32, PP)
          >(_tensor)
          .cast();
  t[51] = Pointer.fromFunction<P Function(P, PP)>(_tensorData).cast();
  t[60] = Pointer.fromFunction<P Function(P, Pointer<Int32>)>(_elementType)
      .cast();
  t[61] = Pointer.fromFunction<P Function(P, Pointer<IntPtr>)>(_dimsCount)
      .cast();
  t[62] = Pointer.fromFunction<P Function(P, Pointer<Int64>, IntPtr)>(_dims)
      .cast();
  t[65] = Pointer.fromFunction<P Function(P, PP)>(_typeAndShape).cast();
  t[69] = Pointer.fromFunction<P Function(Int32, Int32, PP)>(_memory).cast();
  t[92] = Pointer.fromFunction<Void Function(P)>(_relEnv).cast();
  t[93] = Pointer.fromFunction<Void Function(P)>(_relStatus).cast();
  t[94] = Pointer.fromFunction<Void Function(P)>(_relMemory).cast();
  t[95] = Pointer.fromFunction<Void Function(P)>(_relSession).cast();
  t[96] = Pointer.fromFunction<Void Function(P)>(_relValue).cast();
  t[99] = Pointer.fromFunction<Void Function(P)>(_relInfo).cast();
  t[100] = Pointer.fromFunction<Void Function(P)>(_relOptions).cast();
  return t;
}

/// Resets the fake state (for tests that import this file).
void resetOrtFakes() {
  counts.clear();
  elementType = 1;
  failRun = false;
  failSessionNumber = 0;
  _data.asTypedList(4).setAll(0, [1, 2, 3, 4]);
}

void expectBalanced() {
  for (final kind in ['memory', 'value', 'info', 'options']) {
    expect(
      counts['release $kind'] ?? 0,
      counts['create $kind'] ?? 0,
      reason: kind,
    );
  }
}

void main() {
  late OrtSession session;
  late OrtRuntime runtime;

  setUp(() {
    counts.clear();
    elementType = 1;
    failRun = false;
    failSessionNumber = 0;
    _data.asTypedList(4).setAll(0, [1, 2, 3, 4]);
    runtime = OrtRuntime.fromTable(fakeTable());
    session = runtime.open('/model.onnx');
  });

  test('Lauf liest die Ausgabe und gibt alles frei', () {
    final out = session.run('in', Float32List(4), [1, 4], 'out');
    expect(out.shape, [1, 4]);
    expect(out.data, [1, 2, 3, 4]);
    expect(counts['create value'], 2); // Eingabe und Ergebnis
    expectBalanced();
  });

  test('mehrere Läufe häufen nichts an', () {
    for (var i = 0; i < 5; i++) {
      session.run('in', Float32List(4), [1, 4], 'out');
    }
    expect(counts['create value'], 10);
    expectBalanced();
  });

  test('anderer Ausgabetyp: OrtException, trotzdem alles frei', () {
    elementType = 11; // double
    expect(
      () => session.run('in', Float32List(4), [1, 4], 'out'),
      throwsA(isA<OrtException>()),
    );
    expectBalanced();
  });

  test('Fehler im Lauf: Status wird freigegeben, Eingabe auch', () {
    failRun = true;
    expect(
      () => session.run('in', Float32List(4), [1, 4], 'out'),
      throwsA(isA<OrtException>()),
    );
    expect(counts['release status'], 1);
    expectBalanced();
  });

  test('close gibt Sitzung und Umgebung frei, doppelt schadet nicht', () {
    session.close();
    session.close();
    runtime.close();
    expect(counts['release session'], 1);
    expect(counts['release env'], 1);
  });
}
