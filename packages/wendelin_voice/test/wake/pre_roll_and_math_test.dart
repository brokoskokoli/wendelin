import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Int16List ramp(int from, int n) =>
    Int16List.fromList([for (var i = 0; i < n; i++) from + i]);

void main() {
  group('PreRollBuffer', () {
    test('liefert genau die letzten 300 ms, sample-genau', () {
      final b = PreRollBuffer(); // 4800 Samples
      var next = 0;
      for (var i = 0; i < 23; i++) {
        b.add(ramp(next, 480)); // 30 ms Frames
        next += 480;
      }
      final s = b.snapshot();
      expect(s.length, 4800);
      expect(s.first, next - 4800);
      expect(s.last, next - 1);
      for (var i = 1; i < s.length; i++) {
        expect(s[i], s[i - 1] + 1, reason: 'Lücke bei $i');
      }
    });

    test('Frames über Ringgrenze und größer als Kapazität', () {
      final b = PreRollBuffer(capacity: const Duration(milliseconds: 10));
      b.add(ramp(0, 100));
      b.add(ramp(100, 100)); // 160 Samples Kapazität, Umbruch
      expect(b.snapshot(), ramp(40, 160));
      b.add(ramp(1000, 500)); // größer als die Kapazität
      expect(b.snapshot(), ramp(1340, 160));
      expect(b.length, 160);
    });

    test(
      'Obergrenze: Kapazität über 5 s wird abgelehnt, Puffer wächst nie',
      () {
        expect(
          () => PreRollBuffer(capacity: const Duration(seconds: 6)),
          throwsArgumentError,
        );
        expect(
          () => PreRollBuffer(capacity: Duration.zero),
          throwsArgumentError,
        );
        final b = PreRollBuffer();
        for (var i = 0; i < 1000; i++) {
          b.add(ramp(0, 480));
        }
        expect(b.length, 4800);
      },
    );

    test('snapshot(last) und clear', () {
      final b = PreRollBuffer()..add(ramp(0, 1000));
      expect(
        b.snapshot(last: const Duration(milliseconds: 10)),
        ramp(840, 160),
      );
      expect(b.snapshot(last: const Duration(seconds: 1)).length, 1000);
      b.clear();
      expect(b.snapshot(), isEmpty);
    });
  });

  group('Ähnlichkeit und Kandidatenregel', () {
    Float32List v(List<double> x) => Float32List.fromList(x);

    test('cosineSimilarity Tabelle', () {
      final cases = <(List<double>, List<double>, double)>[
        ([1, 0], [1, 0], 1),
        ([1, 0], [0, 1], 0),
        ([1, 0], [-1, 0], -1),
        ([1, 1], [1, 0], 0.7071067811865475),
        ([0, 0], [1, 0], 0),
      ];
      for (final (a, b, want) in cases) {
        expect(cosineSimilarity(v(a), v(b)), closeTo(want, 1e-6));
      }
      expect(() => cosineSimilarity(v([1]), v([1, 2])), throwsArgumentError);
    });

    test('bestSimilarity wählt die ähnlichste Vorlage', () {
      expect(bestSimilarity(v([1, 0]), []), -1);
      expect(
        bestSimilarity(v([1, 0.1]), [
          v([0, 1]),
          v([1, 0]),
        ]),
        closeTo(0.995, 1e-3),
      );
    });

    test('decideCandidate: Modell ODER Vorlage', () {
      final cases = <(double?, double?, double?, double?, CandidateReason?)>[
        // score, sim, modelThr, tmplThr, expected
        (0.6, null, 0.5, null, CandidateReason.model),
        (0.4, null, 0.5, null, null),
        (null, 0.9, null, 0.8, CandidateReason.template),
        (0.1, 0.9, 0.5, 0.8, CandidateReason.template),
        (0.7, 0.5, 0.5, 0.8, CandidateReason.model),
        (0.7, 0.9, 0.5, 0.8, CandidateReason.both),
        (0.5, 0.8, 0.5, 0.8, CandidateReason.both), // Gleichheit zählt
        (0.49, 0.79, 0.5, 0.8, null),
        (0.9, 0.9, null, null, null), // beide Regeln aus
      ];
      for (final (s, sim, mt, tt, want) in cases) {
        final d = decideCandidate(
          modelScore: s,
          templateSimilarity: sim,
          modelThreshold: mt,
          templateThreshold: tt,
        );
        expect(d?.reason, want, reason: '$s $sim $mt $tt');
        if (d != null) expect(d.confidence, inInclusiveRange(0, 1));
      }
    });
  });

  group('WakeTemplates', () {
    test('JSON-Rundlauf enthält nur Embeddings', () {
      final t = WakeTemplates(
        speakerId: 's1',
        featureVersion: 'oww-0.5.1',
        threshold: 0.83,
        embeddings: [
          Float32List.fromList([0.5, -1, 2.25]),
        ],
      );
      final j = t.toJson();
      expect(j.keys, {
        'speakerId',
        'featureVersion',
        'threshold',
        'embeddings',
      });
      final back = WakeTemplates.fromJson(j);
      expect(back.threshold, 0.83);
      expect(back.embeddings.single, [0.5, -1, 2.25]);
      expect(back.isCompatible('oww-0.5.1'), isTrue);
      expect(back.isCompatible('oww-0.6'), isFalse);
      expect(back.withThreshold(0.9).threshold, 0.9);
    });
  });
}
