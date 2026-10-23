import 'dart:math' as math;
import 'dart:typed_data';

import 'wake_math.dart';

/// Limits of the content check of the enrollment (WP140). All values are
/// provisional until the measurement on real recordings is entered (see
/// `docs/testing/m5/WP140.md`); change them here only.
abstract final class WakeEnrollRules {
  /// A recording passes the content check by the classifier alone when its
  /// highest window score (`WakeWindow.modelScore`) reaches this value. The
  /// other way to pass is the recognizer hearing „Wendelin“ (OR).
  static const classifierMinScore = 0.5;

  /// A template is an outlier when its typicality (median centered cosine to
  /// the others) lies more than this far below the median typicality.
  static const outlierMargin = 0.25;

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

/// Indices of [all] that are outliers (typicality more than [margin] below
/// the median typicality), worst first and at most [maxShare] of them.
/// Empty with fewer than [minTemplates] templates.
List<int> outlierIndices(
  List<Float32List> all,
  Float32List mean, {
  double margin = WakeEnrollRules.outlierMargin,
  int minTemplates = WakeEnrollRules.outlierMinTemplates,
  double maxShare = WakeEnrollRules.maxPruneShare,
}) {
  if (all.length < minTemplates) return const [];
  final typical = [
    for (var i = 0; i < all.length; i++) templateTypicality(all, i, mean),
  ];
  final limit = median(typical) - margin;
  final out = [
    for (var i = 0; i < all.length; i++)
      if (typical[i] < limit) i,
  ]..sort((a, b) => typical[a].compareTo(typical[b]));
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
