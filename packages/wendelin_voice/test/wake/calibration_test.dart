import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  group('calibrateThreshold', () {
    test('Tabelle: Ziel 1/h', () {
      final cases =
          <(List<double>, List<double>, double, double, double, double, bool)>[
            // pos, neg events, hours, thr>, recall, fa/h, meets
            // 2 h Hintergrund, 1/h erlaubt = 2 Ereignisse dürfen drüber
            ([0.9, 0.8, 0.7], [0.5, 0.6, 0.65, 0.7], 2, 0.6, 1, 1.0, true),
            ([0.9, 0.8, 0.7], [0.2, 0.3], 2, 0.7, 1, 0, true),
            ([0.9, 0.8, 0.7], [0.95, 0.96, 0.97, 0.2], 1, 0.96, 0, 1, false),
            ([0.9, 0.8, 0.7, 0.6], [0.65, 0.3], 1, 0.3, 1, 1, true),
          ];
      for (final (pos, neg, h, _, recall, fa, meets) in cases) {
        final c = calibrateThreshold(
          positiveScores: pos,
          negativeEvents: neg,
          negativeHours: h,
          minThreshold: 0,
        );
        expect(c.recall, closeTo(recall, 1e-9), reason: '$neg');
        expect(c.falseAlarmsPerHour, closeTo(fa, 1e-9), reason: '$neg');
        expect(c.meetsTarget, meets, reason: '$neg');
      }
    });

    test(
      'Schwelle liegt knapp über dem höchsten auszuschließenden Ereignis',
      () {
        final c = calibrateThreshold(
          positiveScores: [0.9, 0.8],
          negativeEvents: [0.1, 0.2, 0.75, 0.8],
          negativeHours: 1,
          minThreshold: 0,
        );
        expect(c.threshold, greaterThan(0.75));
        expect(c.threshold, lessThan(0.76));
        expect(c.recall, 1);
        expect(c.meetsTarget, isTrue);
      },
    );

    test('strengeres Ziel liefert höhere Schwelle', () {
      final neg = [for (var i = 0; i < 20; i++) 0.3 + i * 0.02];
      final pos = [0.9, 0.85, 0.8];
      final loose = calibrateThreshold(
        positiveScores: pos,
        negativeEvents: neg,
        negativeHours: 2,
        targetPerHour: 5,
        minThreshold: 0,
      );
      final strict = calibrateThreshold(
        positiveScores: pos,
        negativeEvents: neg,
        negativeHours: 2,
        minThreshold: 0,
      );
      expect(strict.threshold, greaterThan(loose.threshold));
      expect(strict.falseAlarmsPerHour, lessThanOrEqualTo(1));
      expect(loose.falseAlarmsPerHour, lessThanOrEqualTo(5));
    });

    test(
      'ohne Hintergrundstunden ArgumentError; ohne Positive Erfolg false',
      () {
        expect(
          () => calibrateThreshold(
            positiveScores: [1],
            negativeEvents: [],
            negativeHours: 0,
          ),
          throwsArgumentError,
        );
        final c = calibrateThreshold(
          positiveScores: [],
          negativeEvents: [0.5],
          negativeHours: 1,
        );
        expect(c.meetsTarget, isFalse);
      },
    );

    test('requireNegatives false: leerer Hintergrund ist verwertbar', () {
      final c = calibrateThreshold(
        positiveScores: [0.9, 0.92, 0.95],
        negativeEvents: [],
        negativeHours: 0.2,
        requireNegatives: false,
      );
      expect(c.meetsTarget, isTrue);
      expect(c.falseAlarmsPerHour, 0);
      expect(c.threshold, wakeUnconstrainedMaxThreshold);
      expect(c.recall, 1);
      expect(
        calibrateThreshold(
          positiveScores: [0.9, 0.92, 0.95],
          negativeEvents: [],
          negativeHours: 0.2,
        ).meetsTarget,
        isFalse,
      );
    });

    group('ohne Ereignisse (leiser Raum)', () {
      test('Schwelle höchstens 0,50, auch bei hohen Positiven', () {
        final c = calibrateThreshold(
          positiveScores: [0.85, 0.8, 0.77, 0.75, 0.9, 0.82],
          negativeEvents: [],
          negativeHours: 0.03,
          requireNegatives: false,
        );
        expect(c.threshold, wakeUnconstrainedMaxThreshold);
        expect(c.recall, 1);
      });

      test('niedrige Positive: Quantil darunter, Untergrenze bleibt', () {
        final low = calibrateThreshold(
          positiveScores: [0.45, 0.46, 0.47],
          negativeEvents: [],
          negativeHours: 0.1,
          requireNegatives: false,
        );
        expect(low.threshold, closeTo(0.45, 1e-9));
        final floor = calibrateThreshold(
          positiveScores: [0.2, 0.3, 0.9],
          negativeEvents: [],
          negativeHours: 0.1,
          requireNegatives: false,
        );
        expect(floor.threshold, wakeMinThreshold);
      });

      test('mit Ereignissen darf die Schwelle über 0,50 liegen', () {
        final c = calibrateThreshold(
          positiveScores: [0.9, 0.85, 0.8],
          negativeEvents: [0.3, 0.6, 0.7],
          negativeHours: 1,
        );
        expect(c.threshold, greaterThan(0.6));
        expect(c.threshold, lessThan(0.61));
      });
    });

    group('robust', () {
      test('Untergrenze: Schwelle nie unter 0,40 (zentrierter Raum)', () {
        final c = calibrateThreshold(
          positiveScores: [0.9, 0.3, 0.2],
          negativeEvents: [0.3, 0.35],
          negativeHours: 2,
        );
        expect(c.threshold, wakeMinThreshold);
        expect(c.recall, closeTo(1 / 3, 1e-9));
        final strict = calibrateThreshold(
          positiveScores: [0.99, 0.98],
          negativeEvents: [0.1, 0.2, 0.3],
          negativeHours: 1,
        );
        expect(strict.threshold, wakeMinThreshold);
      });

      test('Ausreißer 0,1 unter den Positiven senkt die Schwelle nicht', () {
        final pos = [0.1, for (var i = 0; i < 19; i++) 0.42 + i * 0.001];
        final c = calibrateThreshold(
          positiveScores: pos,
          negativeEvents: [0.2],
          negativeHours: 1,
          minThreshold: 0,
        );
        expect(c.threshold, greaterThanOrEqualTo(0.42));
        expect(c.recall, closeTo(19 / 20, 1e-9));
        expect(c.meetsTarget, isTrue);
      });

      test('ein erlaubtes Ereignis hebt den Deckel 0,50 nicht auf', () {
        final c = calibrateThreshold(
          positiveScores: [0.85, 0.8, 0.77, 0.75, 0.9, 0.82],
          negativeEvents: [0.2],
          negativeHours: 1,
        );
        expect(c.threshold, wakeUnconstrainedMaxThreshold);
        expect(c.recall, 1);
      });

      test('nur eine Vorlage: kein Erfolg', () {
        final c = calibrateThreshold(
          positiveScores: [0.95],
          negativeEvents: [0.2],
          negativeHours: 1,
        );
        expect(c.meetsTarget, isFalse);
        final two = calibrateThreshold(
          positiveScores: [0.95, 0.96],
          negativeEvents: [0.2],
          negativeHours: 1,
        );
        expect(two.meetsTarget, isTrue);
      });

      test('keine Negative: kein Erfolg', () {
        final c = calibrateThreshold(
          positiveScores: [0.95, 0.96, 0.97],
          negativeEvents: [],
          negativeHours: 1,
        );
        expect(c.meetsTarget, isFalse);
      });
    });
  });

  test('leaveOneOutScores vergleicht nie mit sich selbst', () {
    Float32List v(List<double> x) => Float32List.fromList(x);
    final s = leaveOneOutScores([
      v([1, 0]),
      v([1, 0]),
      v([0, 1]),
    ]);
    expect(s, [closeTo(1, 1e-9), closeTo(1, 1e-9), closeTo(0, 1e-9)]);
    expect(
      leaveOneOutScores([
        v([1, 0]),
      ]),
      [-1],
    );
  });

  test('leaveOneOutScores zentriert mit dem Mittel (WP134)', () {
    Float32List v(List<double> x) => Float32List.fromList(x);
    final ts = [
      v([6, 5, 5, 5]),
      v([5.7, 5.7, 5, 5]),
    ];
    final raw = leaveOneOutScores(ts);
    final centered = leaveOneOutScores(ts, mean: v([5, 5, 5, 5]));
    expect(raw.first, greaterThan(0.99));
    expect(centered.first, closeTo(0.707, 0.01));
  });
}
