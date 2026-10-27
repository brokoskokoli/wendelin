import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Embeddings of synthetic voices (see test/fixtures/speaker/README.md).
Map<String, List<Float32List>> _fixture() {
  final json = jsonDecode(
    File('test/fixtures/speaker/embeddings.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final voices = json['voices']! as Map<String, Object?>;
  return {
    for (final e in voices.entries)
      e.key: [
        for (final u in e.value! as List)
          Float32List.fromList([
            for (final x in (u as Map)['v'] as List) (x as num).toDouble(),
          ]),
      ],
  };
}

/// Unit vector at angle with cosine [c] to the first axis (dimension 4).
Float32List _at(double c) {
  final s = (1 - c * c) <= 0 ? 0.0 : _sqrt(1 - c * c);
  return Float32List.fromList([c, s, 0, 0]);
}

double _cos(double x) {
  // Taylor series, enough for |x| < 2.
  var term = 1.0;
  var sum = 1.0;
  for (var n = 1; n < 12; n++) {
    term *= -x * x / ((2 * n - 1) * (2 * n));
    sum += term;
  }
  return sum;
}

double _sqrt(double x) {
  var r = x;
  for (var i = 0; i < 40; i++) {
    r = (r + x / r) / 2;
  }
  return r;
}

void main() {
  final voices = _fixture();

  /// Embedder over all fixture embeddings; returns the key of each one.
  late FakeSpeakerEmbedder embedder;
  late InMemorySpeakerProfileStore store;
  late SpeakerIdentifier id;
  late Map<String, List<int>> keys;

  setUp(() {
    final all = <Float32List>[];
    keys = {};
    for (final e in voices.entries) {
      keys[e.key] = [];
      for (final v in e.value) {
        keys[e.key]!.add(all.length);
        all.add(v);
      }
    }
    embedder = FakeSpeakerEmbedder(all);
    store = InMemorySpeakerProfileStore();
    id = SpeakerIdentifier(embedder: embedder, store: store);
  });

  List<Int16List> enrollAudio(String voice, {int n = 5}) => [
    for (final k in keys[voice]!.take(n)) FakeSpeakerEmbedder.audio(k),
  ];
  Int16List testAudio(String voice, int i) =>
      FakeSpeakerEmbedder.audio(keys[voice]![8 + i]);

  Future<void> enrollBoth() async {
    await id.enroll(id: 'a', name: 'Anna', samples: enrollAudio('thorsten'));
    await id.enroll(id: 'b', name: 'Ben', samples: enrollAudio('kerstin'));
  }

  group('Erkennung mit synthetischen Stimmen', () {
    test('zwei Sprecher werden getrennt, jeder Testsatz richtig', () async {
      await enrollBoth();
      for (var i = 0; i < 4; i++) {
        final a = await id.identify(testAudio('thorsten', i));
        final b = await id.identify(testAudio('kerstin', i));
        expect(a.personId, 'a', reason: 'thorsten $i');
        expect(b.personId, 'b', reason: 'kerstin $i');
        expect(a.score, greaterThan(0.6));
      }
    });

    test('fremde Stimme -> unbekannt (belowThreshold)', () async {
      await enrollBoth();
      for (var i = 0; i < 4; i++) {
        final m = await id.identify(testAudio('ljspeech', i));
        expect(m.isKnown, isFalse);
        expect(m.reason, SpeakerUnknownReason.belowThreshold);
      }
    });

    test(
      'Fremder gegen eine einzelne Person ist ebenfalls unbekannt',
      () async {
        await id.enroll(
          id: 'a',
          name: 'Anna',
          samples: enrollAudio('thorsten'),
        );
        final m = await id.identify(testAudio('kerstin', 0));
        expect(m, isA<SpeakerMatch>().having((m) => m.isKnown, 'known', false));
      },
    );

    test('Kalibrierung: Schwelle liegt in [Untergrenze, Obergrenze]', () async {
      final r = await id.enroll(
        id: 'a',
        name: 'Anna',
        samples: enrollAudio('thorsten', n: 8),
      );
      expect(r.profile.threshold, inInclusiveRange(0.45, 0.60));
      expect(r.meanScore, greaterThan(0.8));
      expect(r.minScore, lessThanOrEqualTo(r.meanScore));
    });

    test('zu kurzes Audio -> unbekannt ohne Embedding-Aufruf', () async {
      await enrollBoth();
      final calls = embedder.embedCalls;
      final m = await id.identify(Int16List(15999));
      expect(m.reason, SpeakerUnknownReason.tooShort);
      expect(embedder.embedCalls, calls);
      final ok = await id.identify(
        FakeSpeakerEmbedder.audio(keys['thorsten']![8], seconds: 1),
      );
      expect(ok.personId, 'a', reason: 'genau 1 s genügt');
    });

    test('ohne Profile: unbekannt, Modell wird nicht gefragt', () async {
      final m = await id.identify(testAudio('thorsten', 0));
      expect(m.reason, SpeakerUnknownReason.noProfiles);
      expect(embedder.embedCalls, 0);
    });

    test('Embedder-Fehler -> unbekannt (failed), keine Ausnahme', () async {
      await enrollBoth();
      embedder.failing = true;
      final m = await id.identify(testAudio('thorsten', 0));
      expect(m.reason, SpeakerUnknownReason.failed);
    });
  });

  group('Diagnose (WP160)', () {
    test('Einlernen: eine Zeile ohne Namen mit Schwelle und Scores', () async {
      final lines = <String>[];
      final logged = SpeakerIdentifier(
        embedder: embedder,
        store: store,
        diagnostics: lines.add,
      );
      await logged.enroll(
        id: 'a',
        name: 'Geheimname',
        samples: enrollAudio('thorsten'),
      );
      expect(
        lines.single,
        matches(
          r'^speaker-enroll samples=5 thr=0\.\d\d clamped=(true|false) '
          r'scores=\d\.\d\d/\d\.\d\d$',
        ),
      );
      expect(lines.single, isNot(contains('Geheim')));
    });

    test(
      'Einlernen, Schwelle an der Obergrenze: clamped=true, Werte',
      () async {
        final lines = <String>[];
        final steady = SpeakerIdentifier(
          embedder: FakeSpeakerEmbedder([
            for (var i = 0; i < 3; i++) Float32List.fromList([1, 0, 0, 0]),
          ]),
          store: store,
          diagnostics: lines.add,
        );
        await steady.enroll(
          id: 'b',
          name: 'B',
          samples: [for (var i = 0; i < 3; i++) FakeSpeakerEmbedder.audio(i)],
        );
        expect(
          lines.single,
          'speaker-enroll samples=3 thr=0.60 clamped=true scores=1.00/1.00',
        );
      },
    );

    test('unter Schwelle: Score, Schwelle und Zweitbester stehen dabei', () {
      SpeakerProfile p(String pid, List<double> v) => SpeakerProfile(
        id: pid,
        name: pid,
        embeddings: [normalized(Float32List.fromList(v))],
        threshold: 0.5,
        createdAt: DateTime.utc(2026),
      );
      final m = SpeakerIdentifier.decide(
        normalized(Float32List.fromList([0, 0, 1, 0.1])),
        [
          p('a', [1, 0, 0.5, 0]),
          p('b', [0, 1, 0.3, 0]),
        ],
      );
      expect(m.reason, SpeakerUnknownReason.belowThreshold);
      expect(m.score, lessThan(0.5));
      expect(m.threshold, 0.5);
      expect(m.second, isNotNull);
      expect(m.profileCount, 2);
    });

    test('mehrdeutig: ambiguous trägt Score, Schwelle, Zweitbesten', () {
      SpeakerProfile p(String pid, List<double> v) => SpeakerProfile(
        id: pid,
        name: pid,
        embeddings: [normalized(Float32List.fromList(v))],
        threshold: 0.5,
        createdAt: DateTime.utc(2026),
      );
      final m = SpeakerIdentifier.decide(
        normalized(Float32List.fromList([1, 0.05, 0, 0])),
        [
          p('a', [1, 0.1, 0, 0]),
          p('b', [1, 0.2, 0, 0]),
        ],
      );
      expect(m.reason, SpeakerUnknownReason.ambiguous);
      expect(m.threshold, 0.5);
      expect(m.second, isNotNull);
      expect(m.second, lessThanOrEqualTo(m.score!));
      expect(m.profileCount, 2);
    });

    test('Embedder-Fehler: failed mit Fehlertyp, nicht still', () async {
      await enrollBoth();
      embedder.failing = true;
      final m = await id.identify(testAudio('thorsten', 0));
      expect(m.reason, SpeakerUnknownReason.failed);
      expect(m.failure, 'stateerror');
      expect(m.profileCount, 2);
      expect(
        speakerLogLine(
          result: 'unknown',
          reason: 'failed',
          audioMs: 2000,
          ms: 5,
          match: m,
        ),
        endsWith('profiles=2 error=stateerror'),
      );
    });

    test('Treffer trägt Score, Schwelle, Zweitbesten und Anzahl', () async {
      await enrollBoth();
      final m = await id.identify(testAudio('thorsten', 0));
      expect(m.isKnown, isTrue);
      expect(m.score, greaterThan(m.threshold!));
      expect(
        m.threshold,
        greaterThanOrEqualTo(SpeakerIdentifier.thresholdFloor),
      );
      expect(m.second, lessThan(m.score!));
      expect(m.profileCount, 2);
    });

    test('zu kurz / ohne Profile: Anzahl der Profile steht dabei', () async {
      expect((await id.identify(Int16List(10))).profileCount, 0);
      await enrollBoth();
      final m = await id.identify(Int16List(100));
      expect(m.reason, SpeakerUnknownReason.tooShort);
      expect(m.profileCount, 2);
    });
  });

  group('Schwelle', () {
    SpeakerProfile profile(String pid, Float32List e, double threshold) =>
        SpeakerProfile(
          id: pid,
          name: pid,
          embeddings: [e],
          threshold: threshold,
          createdAt: DateTime.utc(2026),
        );

    test('knapp darunter unbekannt, knapp darüber erkannt', () {
      final p = profile('a', _at(1), 0.6);
      expect(SpeakerIdentifier.decide(_at(0.59), [p]).isKnown, isFalse);
      expect(SpeakerIdentifier.decide(_at(0.61), [p]).personId, 'a');
    });

    test(
      'eine zu niedrige gespeicherte Schwelle gilt nicht unter der Untergrenze',
      () {
        final p = profile('a', _at(1), 0.1);
        expect(SpeakerIdentifier.decide(_at(0.44), [p]).isKnown, isFalse);
        expect(SpeakerIdentifier.decide(_at(0.46), [p]).personId, 'a');
      },
    );

    test('zwei fast gleiche Personen -> mehrdeutig statt geraten', () {
      final a = profile('a', _at(1), 0.5);
      final b = profile('b', _at(0.8), 0.5);
      final m = SpeakerIdentifier.decide(
        Float32List.fromList([0.9487, 0.3162, 0, 0]),
        [a, b],
      );
      expect(m.reason, SpeakerUnknownReason.ambiguous);
      expect(SpeakerIdentifier.decide(_at(1), [a, b]).personId, 'a');
    });

    test('mehrdeutig auch, wenn der Beste hinten steht', () {
      final a = profile('a', _at(1), 0.5);
      final b = profile('b', _at(0.8), 0.5);
      final m = SpeakerIdentifier.decide(
        Float32List.fromList([0.9487, 0.3162, 0, 0]),
        [b, a],
      );
      expect(m.reason, SpeakerUnknownReason.ambiguous);
    });

    test('Kalibrierung zieht die Streuung ab, Klammer begrenzt', () {
      expect(
        SpeakerIdentifier.calibrateThreshold([0.8, 0.8, 0.8]),
        closeTo(0.8, 1e-9),
      );
      expect(
        SpeakerIdentifier.calibrateThreshold([0.9, 0.5, 0.7]),
        closeTo(0.7 - 2 * 0.1633, 1e-3),
      );
    });

    test('Profil mit anderer Embedding-Länge wird übergangen', () {
      final p = profile('a', Float32List.fromList([1, 0]), 0.5);
      expect(
        SpeakerIdentifier.decide(_at(1), [p]).reason,
        SpeakerUnknownReason.failed,
      );
    });
  });

  group('Einlernen', () {
    test('zu wenige Sätze und zu kurze Aufnahmen werden abgelehnt', () async {
      await expectLater(
        id.enroll(id: 'a', name: 'A', samples: enrollAudio('thorsten', n: 2)),
        throwsA(
          isA<SpeakerEnrollException>().having(
            (e) => e.problem,
            'problem',
            SpeakerEnrollProblem.tooFewSamples,
          ),
        ),
      );
      await expectLater(
        id.enroll(
          id: 'a',
          name: 'A',
          samples: [...enrollAudio('thorsten', n: 2), Int16List(100)],
        ),
        throwsA(
          isA<SpeakerEnrollException>().having(
            (e) => e.problem,
            'problem',
            SpeakerEnrollProblem.tooShort,
          ),
        ),
      );
      expect(store.isEmpty, isTrue);
    });

    test('Mindestlänge 1,5 s: eine Probe darunter wird abgelehnt', () async {
      final k = keys['thorsten']!;
      final ok = SpeakerIdentifier.minEnrollAudioSamples;
      expect(ok, 24000);
      Int16List clip(int i, int n) => Int16List(n)..[0] = k[i];
      await expectLater(
        id.enroll(
          id: 'a',
          name: 'A',
          samples: [clip(0, ok), clip(1, ok), clip(2, ok - 1)],
        ),
        throwsA(isA<SpeakerEnrollException>()),
      );
      final r = await id.enroll(
        id: 'a',
        name: 'A',
        samples: [clip(0, ok), clip(1, ok), clip(2, ok)],
      );
      expect(r.profile.id, 'a');
    });

    test(
      'gestreute Kalibrierung: Schwelle an der Untergrenze, markiert',
      () async {
        // Three embeddings 40 degrees apart: leave-one-out scores 0.5/1/0.5,
        // so mean - 2 sigma is far below the floor.
        Float32List at(double deg) {
          final r = deg * 3.141592653589793 / 180;
          return Float32List.fromList([
            _cos(r),
            _cos(r - 1.5707963267948966),
            0,
            0,
          ]);
        }

        final e = FakeSpeakerEmbedder([at(-40), at(0), at(40), at(0)]);
        final scattered = SpeakerIdentifier(embedder: e, store: store);
        final r = await scattered.enroll(
          id: 'a',
          name: 'A',
          samples: [for (var i = 0; i < 3; i++) FakeSpeakerEmbedder.audio(i)],
        );
        expect(r.minScore, greaterThanOrEqualTo(0.45));
        expect(r.profile.threshold, SpeakerIdentifier.thresholdFloor);
        expect(r.thresholdClamped, isTrue);
        // A very steady voice hits the ceiling.
        final steady = SpeakerIdentifier(
          embedder: FakeSpeakerEmbedder([at(0), at(0), at(0)]),
          store: store,
        );
        final s = await steady.enroll(
          id: 'b',
          name: 'B',
          samples: [for (var i = 0; i < 3; i++) FakeSpeakerEmbedder.audio(i)],
        );
        expect(s.profile.threshold, SpeakerIdentifier.thresholdCeiling);
        expect(s.thresholdClamped, isTrue);
      },
    );

    test('gemischte Sprecher: abgelehnt, nichts gespeichert', () async {
      final mixed = [
        ...enrollAudio('thorsten', n: 2),
        FakeSpeakerEmbedder.audio(keys['ljspeech']![0]),
      ];
      await expectLater(
        id.enroll(id: 'a', name: 'A', samples: mixed),
        throwsA(
          isA<SpeakerEnrollException>().having(
            (e) => e.problem,
            'problem',
            SpeakerEnrollProblem.inconsistent,
          ),
        ),
      );
      expect(store.isEmpty, isTrue);
      expect(await id.profiles(), isEmpty);
    });

    test('Embedder-Fehler beim Einlernen', () async {
      embedder.failing = true;
      await expectLater(
        id.enroll(id: 'a', name: 'A', samples: enrollAudio('thorsten')),
        throwsA(
          isA<SpeakerEnrollException>().having(
            (e) => e.problem,
            'problem',
            SpeakerEnrollProblem.failed,
          ),
        ),
      );
    });

    test('erneutes Einlernen derselben Person ersetzt das Profil', () async {
      await id.enroll(id: 'a', name: 'Anna', samples: enrollAudio('thorsten'));
      await id.enroll(id: 'a', name: 'Anna', samples: enrollAudio('kerstin'));
      expect((await id.profiles()).length, 1);
      expect((await id.identify(testAudio('kerstin', 0))).personId, 'a');
    });
  });

  group('Speicher', () {
    test('Profile überleben einen Neustart (frischer Identifier)', () async {
      await enrollBoth();
      final again = SpeakerIdentifier(embedder: embedder, store: store);
      expect((await again.identify(testAudio('kerstin', 1))).personId, 'b');
    });

    test('Person löschen entfernt sie vollständig', () async {
      await enrollBoth();
      await id.remove('a');
      expect((await id.identify(testAudio('thorsten', 0))).isKnown, isFalse);
      expect(store.dump, isNot(contains('Anna')));
      expect(store.dump, contains('Ben'));
      expect((await store.load()).map((p) => p.id), ['b']);
    });

    test(
      'Löschen über einen zweiten Identifier gilt sofort (kein Cache)',
      () async {
        await enrollBoth();
        final other = SpeakerIdentifier(embedder: embedder, store: store);
        expect((await id.identify(testAudio('thorsten', 0))).isKnown, isTrue);
        await other.remove('a');
        expect((await id.identify(testAudio('thorsten', 0))).isKnown, isFalse);
        expect((await id.identify(testAudio('kerstin', 0))).personId, 'b');
        await other.removeAll();
        expect(
          (await id.identify(testAudio('kerstin', 0))).reason,
          SpeakerUnknownReason.noProfiles,
        );
      },
    );

    test('alles löschen leert den Speicher', () async {
      await enrollBoth();
      await id.removeAll();
      expect(store.isEmpty, isTrue);
      expect(await id.hasProfiles, isFalse);
    });

    test('Release gibt das Modell frei', () async {
      await id.release();
      expect(embedder.releases, 1);
    });

    test('JSON-Codec: Rundlauf; kaputte Einträge werden verworfen', () {
      final p = SpeakerProfile(
        id: 'a',
        name: 'Anna',
        embeddings: [_at(1), _at(0.9)],
        threshold: 0.5,
        createdAt: DateTime.utc(2026, 10, 19),
      );
      final back = SpeakerProfile.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.embeddings.length, 2);
      expect(back.embeddings[1][0], closeTo(0.9, 1e-6));
      expect(back.threshold, 0.5);
      expect(SpeakerProfile.fromJson({'id': 'a'}), isNull);
      expect(SpeakerProfile.fromJson('x'), isNull);
      expect(
        SpeakerProfile.fromJson({
          ...p.toJson(),
          'embeddings': ['AAAA'],
        }),
        isNull,
        reason: '3 Bytes sind kein Float32',
      );
    });

    test('Treffer zeigt in toString keinen Namen', () {
      const m = SpeakerMatch.known(personId: 'a', name: 'Anna', score: 0.8);
      expect('$m', isNot(contains('Anna')));
    });
  });
}
