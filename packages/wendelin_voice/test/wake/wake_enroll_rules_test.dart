import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

Float32List v(List<double> x) => Float32List.fromList(x);

void main() {
  final mean = Float32List(3);
  List<Float32List> group(int n) => [
    for (var i = 0; i < n; i++) v([1, 0.03 * i, 0.2]),
  ];

  test('median: ungerade und gerade Anzahl', () {
    expect(median([3, 1, 2]), 2);
    expect(median([4, 1, 2, 3]), 2.5);
  });

  test('Typikalität: ein Ausreißer liegt weit unter den anderen', () {
    final all = [
      ...group(6),
      v([-1, 0.8, -0.5]),
    ];
    expect(
      templateTypicality(all, 6, mean),
      lessThan(templateTypicality(all, 0, mean) - 0.5),
    );
  });

  test('Abweichung: Ausreißer stark negativ, passende Vorlage nahe 0', () {
    final all = [
      ...group(6),
      v([-1, 0.8, -0.5]),
    ];
    final dev = templateDeviations(all, mean);
    expect(dev[6], lessThan(-0.5));
    expect(dev[0].abs(), lessThan(0.1));
  });

  test('Rand: Abweichung genau am Limit ist kein Ausreißer', () {
    final all = [
      ...group(6),
      v([-1, 0.8, -0.5]),
    ];
    final gap = -templateDeviations(all, mean)[6];
    expect(outlierIndices(all, mean, margin: gap - 0.01), contains(6));
    expect(outlierIndices(all, mean, margin: gap + 0.01), isEmpty);
  });

  test('Schwellen aus der Messung', () {
    expect(WakeEnrollRules.classifierMinScore, 0.9);
    expect(WakeEnrollRules.outlierMargin, 0.2);
  });

  test('pruneOutliers entfernt und zählt', () {
    final all = [
      ...group(8),
      v([-1, 0.8, -0.5]),
    ];
    final r = pruneOutliers(all, mean);
    expect(r.removed, 1);
    expect(r.kept, hasLength(8));
    expect(pruneOutliers(r.kept, mean).removed, 0, reason: 'idempotent');
  });

  test('Deckel: höchstens 25 % werden entfernt, die schlechtesten zuerst', () {
    final all = [
      ...group(8),
      v([-1, 0.8, -0.5]),
      v([-1, -0.8, 0.1]),
      v([0, -1, -1]),
      v([-0.2, 1, -1]),
    ];
    final dev = templateDeviations(all, mean);
    final bad = [
      for (var i = 8; i < 12; i++)
        if (dev[i] < -WakeEnrollRules.outlierMargin) i,
    ];
    expect(bad, hasLength(4), reason: 'Aufbau: alle vier wären Ausreißer');
    final out = outlierIndices(all, mean);
    expect(out, hasLength(3), reason: 'Deckel 25 % von 12');
    final worst = [...bad]..sort((a, b) => dev[a].compareTo(dev[b]));
    expect(out, worst.take(3).toList());
    expect(pruneOutliers(all, mean).removed, 3);
  });
}
