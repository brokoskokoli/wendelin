import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/onnx_wake_models.dart';
import 'package:wendelin/platform/voice/ort_session.dart';

import 'ort_session_test.dart'
    show counts, failSessionNumber, fakeTable, resetOrtFakes;

void main() {
  late OrtRuntime runtime;

  setUp(() {
    resetOrtFakes();
    runtime = OrtRuntime.fromTable(fakeTable());
  });

  test('ohne Klassifikator: zwei Sitzungen, kein Score', () {
    final m = OnnxWakeModels.open('/m', runtime: runtime);
    expect(counts['create session'], 2);
    expect(m.hasClassifier, isFalse);
    expect(() => m.classify(Float32List(1536)), throwsStateError);
    m.close();
    expect(counts['release session'], 2);
  });

  test('mit Klassifikator: dritte Sitzung, Score aus der Ausgabe', () {
    final m = OnnxWakeModels.open(
      '/m',
      runtime: runtime,
      classifierPath: '/c/wendelin_wp130_a.onnx',
    );
    expect(counts['create session'], 3);
    expect(m.hasClassifier, isTrue);
    expect(m.classify(Float32List(1536)), 1); // erster Wert der Fake-Ausgabe
    m.close();
    expect(counts['release session'], 3);
  });

  test('falsche Fensterlänge: Fehler statt Score', () {
    final m = OnnxWakeModels.open(
      '/m',
      runtime: runtime,
      classifierPath: '/c.onnx',
    );
    expect(() => m.classify(Float32List(96)), throwsArgumentError);
    m.close();
  });

  test('Klassifikator nicht ladbar: Fehler, die beiden anderen Sitzungen '
      'werden geschlossen', () {
    failSessionNumber = 3;
    expect(
      () => OnnxWakeModels.open(
        '/m',
        runtime: runtime,
        classifierPath: '/fehlt.onnx',
      ),
      throwsA(isA<OrtException>()),
    );
    expect(counts['release session'], 2);
  });

  test('Einbettungsmodell nicht ladbar: Mel-Sitzung wird geschlossen', () {
    failSessionNumber = 2;
    expect(
      () => OnnxWakeModels.open('/m', runtime: runtime),
      throwsA(isA<OrtException>()),
    );
    expect(counts['release session'], 1);
  });
}
