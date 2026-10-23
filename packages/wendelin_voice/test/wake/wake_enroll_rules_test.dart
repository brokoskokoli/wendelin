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

  test('Rand: Abstand genau am Limit ist kein Ausreißer', () {
    final all = [
      ...group(6),
      v([-1, 0.8, -0.5]),
    ];
    final typical = [
      for (var i = 0; i < all.length; i++) templateTypicality(all, i, mean),
    ];
    final gap = median(typical) - typical[6];
    expect(outlierIndices(all, mean, margin: gap - 0.01), contains(6));
    expect(outlierIndices(all, mean, margin: gap + 0.01), isEmpty);
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
}
