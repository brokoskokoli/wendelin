// WP129: Stufe 1 entscheidet mit dem Spitzenwert des Ereignisses (Halten ab
// Band-Eintritt), nicht mit dem ersten Fenster im Band.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const _band = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.995);

/// Feeds [scores] one window each; returns the hits as (window index, hit).
Future<List<(int, WakeWordHit)>> _run(
  List<double?> scores, {
  int hold = 5,
  int drops = 1,
}) async {
  var i = 0;
  final e = CandidateWakeEngine(
    features: FakeWakeFeatureExtractor(
      windowEvery: 100,
      windowFor: (end, _) => WakeWindow(
        endSample: end,
        embedding: Float32List.fromList([0, 1]),
        modelScore: scores[i],
      ),
    ),
    modelThreshold: _band.verifyFrom,
    directThreshold: _band.acceptFrom,
    holdWindows: hold,
    dropsToEnd: drops,
  );
  await e.open([KeywordSpec.wendelin]);
  final hits = <(int, WakeWordHit)>[];
  for (i = 0; i < scores.length; i++) {
    for (final h in await e.accept(Int16List(100))) {
      hits.add((i, h));
    }
  }
  return hits;
}

void main() {
  test(
    'Anstieg im Band bis direkt: sofort bei >= acceptFrom, direkt',
    () async {
      final hits = await _run([0.5, 0.981, 0.99, 0.995, 0.9]);
      expect(hits, hasLength(1));
      expect(hits.single.$1, 3);
      expect(hits.single.$2.direct, isTrue);
      expect(hits.single.$2.score, 0.995);
    },
  );

  test(
    'Spitze im Band: nach dem Abfall mit dem Spitzenwert, nicht direkt',
    () async {
      final hits = await _run([0.5, 0.981, 0.99, 0.985, 0.2]);
      expect(
        hits.single.$1,
        3,
        reason: 'Abfall unter die Spitze beendet das Halten',
      );
      expect(hits.single.$2.score, 0.99);
      expect(hits.single.$2.direct, isFalse);
    },
  );

  test('Halten endet nach holdWindows mit dem Spitzenwert', () async {
    final hits = await _run([0.981, 0.982, 0.983, 0.984, 0.985, 0.986, 0.987]);
    expect(hits.single.$1, 4, reason: 'fünftes Fenster im Band');
    expect(hits.single.$2.score, 0.985);
  });

  test('knapp vor dem Limit (4 Fenster) wird noch gehalten', () async {
    final hits = await _run([0.981, 0.982, 0.983, 0.984, 0.2]);
    expect(hits.single.$1, 4);
    expect(hits.single.$2.score, 0.984);
  });

  test('gleicher Score verlängert das Halten (>= Spitze)', () async {
    final hits = await _run([0.981, 0.99, 0.99, 0.2]);
    expect(
      hits.single.$1,
      3,
      reason: 'gleicher Wert hält weiter, Ende erst beim Abfall',
    );
    expect(hits.single.$2.score, 0.99);
  });

  test('erstes Fenster schon >= acceptFrom: sofort direkt', () async {
    final hits = await _run([0.5, 0.996]);
    expect(hits.single.$1, 1);
    expect(hits.single.$2.direct, isTrue);
  });

  test('unter der unteren Grenze: nie ein Treffer', () async {
    expect(await _run([0.979, 0.9799, 0.5, 0.979]), isEmpty);
  });

  test(
    'Score fehlt im Halten (null): mit dem Spitzenwert entscheiden',
    () async {
      final hits = await _run([0.981, 0.99, null]);
      expect(hits.single.$1, 2);
      expect(hits.single.$2.score, 0.99);
    },
  );

  test(
    'holdWindows 0: erstes Fenster im Band entscheidet (wie bisher)',
    () async {
      final hits = await _run([0.981, 0.99, 0.996], hold: 0);
      expect(hits.single.$1, 0);
      expect(hits.single.$2.score, 0.981);
    },
  );

  test(
    'Stufe-2-Fall: ein später höherer Score wird nach dem Halten direkt',
    () async {
      // Früher: Treffer beim ersten Fenster (0.981, Stufe 2). Jetzt: Spitze.
      final hits = await _run([0.981, 0.985, 0.9951]);
      expect(hits.single.$1, 2);
      expect(hits.single.$2.direct, isTrue);
    },
  );

  group('dropsToEnd', () {
    test('2: ein einzelnes Absinken beendet das Halten nicht, der spätere '
        'Anstieg über acceptFrom entscheidet direkt', () async {
      final hits = await _run([0.5, 0.9917, 0.9892, 0.998], drops: 2);
      expect(hits.single.$1, 3);
      expect(hits.single.$2.direct, isTrue);
      expect(hits.single.$2.score, 0.998);
    });

    test('1 (Standard): dasselbe Muster endet beim ersten Absinken', () async {
      final hits = await _run([0.5, 0.9917, 0.9892, 0.998]);
      expect(hits.first.$1, 2);
      expect(hits.first.$2.score, 0.9917);
      expect(hits.first.$2.direct, isFalse);
    });

    test(
      '2: zwei aufeinanderfolgende Absinken beenden es mit der Spitze',
      () async {
        final hits = await _run([0.99, 0.985, 0.984, 0.998], drops: 2);
        expect(hits.first.$1, 2, reason: 'zweites Absinken in Folge');
        expect(hits.first.$2.score, 0.99);
        expect(hits.first.$2.direct, isFalse);
      },
    );

    test(
      '2: ein Fenster auf/über der Spitze setzt die Zählung zurück',
      () async {
        // Absinken, Gleichstand (>= Spitze), Absinken: nie zwei in Folge.
        final hits = await _run([0.99, 0.985, 0.99, 0.985, 0.2], drops: 2);
        expect(
          hits.single.$1,
          4,
          reason: 'Ende erst am Limit/zweiten Absinken',
        );
        expect(hits.single.$2.score, 0.99);
      },
    );

    test('Absinken zählt zum Limit holdWindows', () async {
      final hits = await _run([0.99, 0.985, 0.99, 0.985, 0.99, 0.99], drops: 3);
      expect(hits.single.$1, 4, reason: 'fünftes Fenster = Limit');
    });

    test('2: Absinken unter die untere Grenze und null zählen mit', () async {
      expect((await _run([0.99, 0.5, 0.5, 0.998], drops: 2)).first.$1, 2);
      expect((await _run([0.99, null, null, 0.998], drops: 2)).first.$1, 2);
      expect((await _run([0.99, double.nan, 0.5, 0.9], drops: 2)).first.$1, 2);
    });

    test('Spitze nach einem Absinken wird die neue Spitze', () async {
      final hits = await _run([0.981, 0.98, 0.99, 0.2, 0.2], drops: 2);
      expect(hits.single.$1, 4);
      expect(hits.single.$2.score, 0.99);
    });

    test('Zustand ist nach dem Ereignis frei (zweites Ereignis neu)', () async {
      final hits = await _run([
        0.99,
        0.2,
        0.2,
        ...List.filled(250, 0.1),
        0.985,
        0.2,
        0.2,
      ], drops: 2);
      expect(hits.map((h) => h.$2.score), [0.99, 0.985]);
    });

    test('dropsToEnd < 1 ist ein Programmierfehler', () {
      expect(
        () => CandidateWakeEngine(
          features: FakeWakeFeatureExtractor(windowEvery: 100),
          dropsToEnd: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('NaN-Score (fail-closed)', () {
    const nan = double.nan;

    test('NaN allein löst nie aus (mit und ohne Halten)', () async {
      expect(await _run([nan, nan, nan]), isEmpty);
      expect(await _run([nan, nan], hold: 0), isEmpty);
    });

    test('NaN vor dem Band wird nie zur Spitze: Band danach zählt', () async {
      final hits = await _run([nan, 0.99, 0.2]);
      expect(hits, hasLength(1));
      expect(hits.single.$2.score, 0.99);
    });

    test('NaN nach Band-Eintritt gibt die endliche Spitze frei', () async {
      final hits = await _run([0.99, nan, 0.2]);
      expect(hits, hasLength(1));
      expect(hits.single.$2.score, 0.99);
    });

    test('decideCandidate: NaN ist kein Kandidat', () {
      expect(
        decideCandidate(
          modelScore: nan,
          templateSimilarity: null,
          modelThreshold: 0.98,
          templateThreshold: null,
        ),
        isNull,
      );
    });
  });
}
