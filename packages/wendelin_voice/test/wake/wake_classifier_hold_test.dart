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
}
