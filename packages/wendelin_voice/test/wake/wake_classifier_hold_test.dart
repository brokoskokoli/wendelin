// WP129/WP141: stage 1 decides with the **peak** of the event, observed from
// the first window in the band for `holdDuration` (inclusive).
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const _band = WakeScoreBand(verifyFrom: 0.98, acceptFrom: 0.995);

/// Window of 80 ms (1280 samples at 16 kHz).
const _w = 1280;

/// Feeds [scores] one 80 ms window each; returns the hits as (window index
/// of the decision, hit).
Future<List<(int, WakeWordHit)>> _run(
  List<double?> scores, {
  Duration hold = const Duration(milliseconds: 800),
}) async {
  var i = 0;
  final e = CandidateWakeEngine(
    features: FakeWakeFeatureExtractor(
      windowEvery: _w,
      windowFor: (end, _) => WakeWindow(
        endSample: end,
        embedding: Float32List.fromList([0, 1]),
        modelScore: scores[i],
      ),
    ),
    modelThreshold: _band.verifyFrom,
    directThreshold: _band.acceptFrom,
    holdDuration: hold,
  );
  await e.open([KeywordSpec.wendelin]);
  final hits = <(int, WakeWordHit)>[];
  for (i = 0; i < scores.length; i++) {
    for (final h in await e.accept(Int16List(_w))) {
      hits.add((i, h));
    }
  }
  return hits;
}

/// [lead] low windows, the event windows, then 12 low windows (the hold ends).
List<double?> _call(List<double?> event, {int lead = 1}) => [
  ...List.filled(lead, 0.1),
  ...event,
  ...List.filled(12, 0.1),
];

void main() {
  test(
    'Anstieg im Band bis direkt: sofort bei >= acceptFrom, direkt',
    () async {
      final hits = await _run([0.5, 0.981, 0.99, 0.995, 0.9]);
      expect(hits, hasLength(1));
      expect(hits.single.$1, 3);
      expect(hits.single.$2.direct, isTrue);
      expect(hits.single.$2.score, 0.995);
      expect(hits.single.$2.holdMs, 160, reason: '2 Fenster nach dem ersten');
      expect(hits.single.$2.endSample, 4 * _w);
    },
  );

  test('Spitze im Band: Abfall beendet nichts, nach 0,8 s entscheidet die '
      'Spitze, Trefferzeit ist das Spitzenfenster', () async {
    final hits = await _run(_call([0.981, 0.99, 0.985, 0.2]));
    // First band window index 1 -> decision window index 11 (+0.80 s).
    expect(hits.single.$1, 11);
    expect(hits.single.$2.score, 0.99);
    expect(hits.single.$2.direct, isFalse);
    expect(hits.single.$2.endSample, 3 * _w, reason: 'Spitzenfenster');
    expect(hits.single.$2.holdMs, 800);
  });

  test('Spitze bei +0,80 s zählt noch, bei +0,88 s nicht', () async {
    List<double?> series(int peakAt) =>
        [0.1, 0.981, ...List.filled(12, 0.5)]..[1 + peakAt] = 0.995 - 0.0001;
    final in80 = await _run(series(10));
    expect(in80.single.$2.score, closeTo(0.9949, 1e-9));
    expect(in80.single.$1, 11);
    expect(in80.single.$2.endSample, 12 * _w);
    final at88 = await _run(series(11));
    expect(at88.single.$2.score, 0.981, reason: '+0,88 s zählt nicht');
    expect(at88.single.$1, 11);
  });

  test('gleicher Score: das spätere Fenster ist die Spitze', () async {
    final hits = await _run(_call([0.981, 0.99, 0.99, 0.2]));
    expect(hits.single.$2.endSample, 4 * _w);
    expect(hits.single.$2.score, 0.99);
  });

  test('erstes Fenster schon >= acceptFrom: sofort direkt, holdMs 0', () async {
    final hits = await _run([0.5, 0.996]);
    expect(hits.single.$1, 1);
    expect(hits.single.$2.direct, isTrue);
    expect(hits.single.$2.holdMs, 0);
  });

  test('unter der unteren Grenze: nie ein Treffer', () async {
    expect(await _run(_call([0.979, 0.9799, 0.5, 0.979])), isEmpty);
  });

  test('Score fehlt (null) im Halten: beendet nichts', () async {
    final hits = await _run(_call([0.981, null, 0.99, null]));
    expect(hits.single.$1, 11);
    expect(hits.single.$2.score, 0.99);
  });

  test('ein später höherer Score wird nach dem Halten direkt', () async {
    final hits = await _run([0.981, 0.985, ...List.filled(5, 0.2), 0.9951]);
    expect(hits.single.$1, 7);
    expect(hits.single.$2.direct, isTrue);
  });

  test('Wert >= acceptFrom nach einem Abfall unter das Band: direkt', () async {
    final hits = await _run([0.99, 0.5, 0.2, 0.9951]);
    expect(hits.single.$1, 3);
    expect(hits.single.$2.direct, isTrue);
  });

  test(
    'holdDuration 0: erstes Fenster im Band entscheidet (wie bisher)',
    () async {
      final hits = await _run([0.981, 0.99, 0.996], hold: Duration.zero);
      expect(hits.single.$1, 0);
      expect(hits.single.$2.score, 0.981);
      expect(hits.single.$2.holdMs, isNull);
    },
  );

  test('Sperrzeit läuft ab der Spitze: Spitze 1,36 s nach der ersten '
      'gesperrt, auch wenn die Entscheidung später als 1,5 s liegt', () async {
    // Call 1: first window 1, peak 3 (0.24 s), decision 11. Call 2: first 20,
    // peak 22 (1,76 s - 0,24 s = 1,52 s) -> allowed; with peak at 21 blocked.
    List<double?> two(int peak2) => List.filled(40, 0.1)
      ..[1] = 0.981
      ..[3] = 0.99
      ..[19] = 0.981
      ..[peak2] = 0.99;
    final blocked = await _run(two(20));
    expect(blocked, hasLength(1), reason: '1,52 s - 0,24 s = 1,28 s');
    final allowed = await _run(two(22));
    expect(allowed, hasLength(2));
    expect(allowed.last.$2.endSample, 23 * _w);
  });

  test('Zustand ist nach dem Ereignis frei (zweites Ereignis neu)', () async {
    final hits = await _run([
      0.99,
      ...List.filled(12, 0.2),
      ...List.filled(25, 0.1),
      0.985,
      ...List.filled(12, 0.2),
    ]);
    expect(hits.map((h) => h.$2.score), [0.99, 0.985]);
  });

  test('reset verwirft ein laufendes Halten', () async {
    final e = CandidateWakeEngine(
      features: FakeWakeFeatureExtractor(
        windowEvery: _w,
        windowFor: (end, _) => WakeWindow(
          endSample: end,
          embedding: Float32List(2),
          modelScore: 0.99,
        ),
      ),
      modelThreshold: _band.verifyFrom,
      directThreshold: _band.acceptFrom,
      holdDuration: const Duration(milliseconds: 800),
    );
    await e.open([KeywordSpec.wendelin]);
    for (var i = 0; i < 5; i++) {
      expect(await e.accept(Int16List(_w)), isEmpty);
    }
    e.reset();
    // A fresh hold starts: nothing for 10 windows (+0.72 s), the 11th ends it.
    var n = 0;
    for (var i = 0; i < 10; i++) {
      n += (await e.accept(Int16List(_w))).length;
    }
    expect(n, 0);
    expect((await e.accept(Int16List(_w))), hasLength(1));
  });

  group('NaN-Score (fail-closed)', () {
    const nan = double.nan;

    test('NaN allein löst nie aus (mit und ohne Halten)', () async {
      expect(await _run([nan, nan, nan]), isEmpty);
      expect(await _run([nan, nan], hold: Duration.zero), isEmpty);
    });

    test('NaN vor dem Band wird nie zur Spitze: Band danach zählt', () async {
      final hits = await _run(_call([nan, 0.99, 0.2]));
      expect(hits, hasLength(1));
      expect(hits.single.$2.score, 0.99);
    });

    test('NaN im Halten beendet nichts: später höhere Spitze zählt', () async {
      final hits = await _run(_call([0.99, nan, 0.992, 0.2]));
      expect(hits.single.$2.score, 0.992);
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
