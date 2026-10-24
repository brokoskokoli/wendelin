import 'dart:math' as math;
import 'dart:typed_data';

import 'wake_math.dart';

/// Limits of the content check of the enrollment (WP140, WP142), measured on
/// real calls (see `docs/testing/m5/wp140.md`, `wp142.md`); change them here
/// only. The classifier no longer accepts a recording (WP142): v8a rates
/// „Wendelin“ and „Hey Wendelin“ alike (9 of 60 „Wendelin“ alone got through
/// at 0.98), so only the recognizer hearing „Hey Wendelin“ passes.
abstract final class WakeEnrollRules {
  /// A template is an outlier when its deviation ([templateDeviation]) is
  /// below minus this value. Measured (WP142, „Hey Wendelin“, quiet
  /// sentences): at 0.2, 2.3 to 3.0 good templates per enrollment were
  /// dropped, at 0.3 only 0.3 to 1.0; intruders at 0.3: noises 100 %, other
  /// words 84 to 92 %.
  static const outlierMargin = 0.3;

  /// Consistency is judged only with at least this many templates (with
  /// fewer there is no „median of the others“ worth the name).
  static const outlierMinTemplates = 5;

  /// At most this share of the templates is dropped per pass, worst first:
  /// groups of genuinely different recordings (near, far, quiet) must not be
  /// emptied by a margin that is too tight.
  static const maxPruneShare = 0.25;
}

/// Median of [values] (not empty).
double median(List<double> values) {
  final s = [...values]..sort();
  final n = s.length;
  return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
}

/// How typical template [i] is: the median centered cosine to all others.
double templateTypicality(List<Float32List> all, int i, Float32List mean) =>
    median([
      for (var j = 0; j < all.length; j++)
        if (j != i) centeredCosine(all[i], all[j], mean),
    ]);

/// Deviation of template [i]: its typicality (median centered cosine to the
/// others) minus the median centered cosine of the other templates among
/// themselves. Around 0 for a template that fits in, clearly negative for
/// an outlier. [sim] is the pairwise centered cosine ([similarityMatrix]).
double templateDeviation(List<List<double>> sim, int i) {
  final n = sim.length;
  final own = median([
    for (var j = 0; j < n; j++)
      if (j != i) sim[i][j],
  ]);
  final others = [
    for (var j = 0; j < n; j++)
      if (j != i)
        for (var k = j + 1; k < n; k++)
          if (k != i) sim[j][k],
  ];
  return own - median(others);
}

/// Pairwise centered cosine of [all].
List<List<double>> similarityMatrix(List<Float32List> all, Float32List mean) {
  final n = all.length;
  final sim = [for (var i = 0; i < n; i++) List<double>.filled(n, 1)];
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      sim[i][j] = sim[j][i] = centeredCosine(all[i], all[j], mean);
    }
  }
  return sim;
}

/// The [templateDeviation] of every template in [all].
List<double> templateDeviations(List<Float32List> all, Float32List mean) {
  final sim = similarityMatrix(all, mean);
  return [for (var i = 0; i < all.length; i++) templateDeviation(sim, i)];
}

/// Indices of [all] that are outliers (deviation below minus [margin]),
/// worst first and at most [maxShare] of them. Empty with fewer than
/// [minTemplates] templates.
List<int> outlierIndices(
  List<Float32List> all,
  Float32List mean, {
  double margin = WakeEnrollRules.outlierMargin,
  int minTemplates = WakeEnrollRules.outlierMinTemplates,
  double maxShare = WakeEnrollRules.maxPruneShare,
}) {
  if (all.length < minTemplates) return const [];
  final dev = templateDeviations(all, mean);
  final out = [
    for (var i = 0; i < all.length; i++)
      if (dev[i] < -margin) i,
  ]..sort((a, b) => dev[a].compareTo(dev[b]));
  final cap = math.max(1, (all.length * maxShare).floor());
  return out.length > cap ? out.sublist(0, cap) : out;
}

/// Result of [pruneOutliers].
final class PruneResult {
  /// Creates a result.
  const PruneResult(this.kept, this.removed);

  /// Templates that stay.
  final List<Float32List> kept;

  /// How many were dropped.
  final int removed;
}

/// [all] without its outliers ([outlierIndices], one pass).
PruneResult pruneOutliers(
  List<Float32List> all,
  Float32List mean, {
  double margin = WakeEnrollRules.outlierMargin,
}) {
  final drop = outlierIndices(all, mean, margin: margin).toSet();
  return PruneResult([
    for (var i = 0; i < all.length; i++)
      if (!drop.contains(i)) all[i],
  ], drop.length);
}
