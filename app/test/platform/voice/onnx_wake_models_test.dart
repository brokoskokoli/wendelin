import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/onnx_wake_models.dart';
import 'package:wendelin/platform/voice/ort_session.dart';

import 'ort_session_test.dart'
    show counts, failRun, failSessionNumber, fakeTable, resetOrtFakes;

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

  // WP171: the classifier as a second opinion in the developer mode.
  group('Klassifikator optional', () {
    test('nicht ladbar: Kette ohne Klassifikator, eine Meldung, kein Wurf', () {
      failSessionNumber = 3;
      final issues = <String>[];
      final m = OnnxWakeModels.open(
        '/m',
        runtime: runtime,
        classifierPath: '/fehlt.onnx',
        classifierOptional: true,
        onClassifierIssue: issues.add,
      );
      expect(m.hasClassifier, isFalse);
      expect(issues, ['open-failed']);
      expect(
        counts['release session'] ?? 0,
        0,
        reason: 'mel/emb bleiben offen',
      );
      m.close();
      expect(counts['release session'], 2);
    });

    test('Fehler beim Bewerten: einmal NaN, danach ohne Klassifikator', () {
      final issues = <String>[];
      final m = OnnxWakeModels.open(
        '/m',
        runtime: runtime,
        classifierPath: '/c.onnx',
        classifierOptional: true,
        onClassifierIssue: issues.add,
      );
      failRun = true;
      expect(m.classify(Float32List(1536)).isNaN, isTrue);
      expect(m.hasClassifier, isFalse);
      expect(issues, ['run-failed']);
      failRun = false;
      m.close();
      expect(counts['release session'], 3, reason: 'Sitzung nur einmal zu');
    });

    test('Zeit je Bewertung geht an classifyCost', () {
      final times = <Duration>[];
      final m = OnnxWakeModels.open(
        '/m',
        runtime: runtime,
        classifierPath: '/c.onnx',
        classifyCost: times.add,
      );
      m.classify(Float32List(1536));
      m.classify(Float32List(1536));
      expect(times, hasLength(2));
      m.close();
    });

    test('nicht optional: Fehler beim Bewerten wirft weiter', () {
      final m = OnnxWakeModels.open(
        '/m',
        runtime: runtime,
        classifierPath: '/c.onnx',
      );
      failRun = true;
      expect(() => m.classify(Float32List(1536)), throwsA(isA<OrtException>()));
      expect(m.hasClassifier, isTrue);
      failRun = false;
      m.close();
    });
  });
}
