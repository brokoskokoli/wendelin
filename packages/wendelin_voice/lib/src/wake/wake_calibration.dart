import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'wake_math.dart';

/// Result of [calibrateThreshold].
@immutable
final class WakeCalibration {
  /// Creates a result.
  const WakeCalibration({
    required this.threshold,
    required this.recall,
    required this.falseAlarmsPerHour,
    required this.meetsTarget,
  });

  /// Chosen threshold: the lowest value that keeps the false alarm rate at
  /// or below the target (maximal recall under the target).
  final double threshold;

  /// Share of positives at or above [threshold] (0..1).
  final double recall;

  /// Expected false candidates per hour at [threshold].
  final double falseAlarmsPerHour;

  /// Whether the target rate is met with a usable recall. `false` when the
  /// threshold had to be pushed above every positive ([recall] is 0): the
  /// recordings do not separate from the background, record again.
  final bool meetsTarget;

  @override
  String toString() =>
      'WakeCalibration($threshold, recall $recall, $falseAlarmsPerHour/h)';
}

/// Lowest threshold [calibrateThreshold] ever returns (a personal template
/// below it would fire on most speech).
///
/// Value of the **centered** cosine (WP134, `wake_center_mean.g.dart`):
/// quiet synthetic background and noise reach at most 0.37 (V1-zero); real
/// quiet negative recordings with the noise padding of V2b reach 0.47..0.51,
/// evaluation thresholds for 2 false alarms per hour lay at 0.43..0.55.
const wakeMinThreshold = 0.40;

/// Highest threshold [calibrateThreshold] picks when no background event
/// forces a higher one (none, or all within the allowed rate; WP134): the provisional threshold of the enrolment.
///
/// Leave-one-out inside one session is optimistic; its 10 % quantile lay at
/// 0.66..0.73 in a quiet room and cut "Wendelin" to 11..23 of 30 hits (fixed
/// 0.50: 29 of 30). Unless background events force it, the threshold
/// therefore never rises above this value (the lower bound [wakeMinThreshold] still holds).
///
/// 0.58 since WP142 (templates of "Hey Wendelin", only blocks 4..6, so no
/// leak into the classifier training): 28 of 30 hits at 0.58 (30 of 30 at
/// 0.50); real negative recordings peak at 0.52 at most, television at 0.53.
/// Older "Wendelin" templates get the same cap (13 of 15 and 29 of 30 hits).
const wakeUnconstrainedMaxThreshold = 0.58;

/// Fewest templates (and thus leave-one-out scores) a calibration needs.
const wakeMinTemplates = 2;

/// Share of positives allowed below the threshold when negatives do not
/// constrain it (a single odd recording must not lower it).
const wakePositiveQuantile = 0.1;

/// Picks the similarity threshold for personal templates.
///
/// [positiveScores] are the best template similarities of the speaker's own
/// utterances (use leave-one-out: never score an utterance against itself).
/// [negativeEvents] are the similarity peaks of background audio, **one per
/// event** (already separated by the refractory time) and [negativeHours]
/// the length of that background. The result is the lowest threshold with
/// `events at/above / negativeHours <= targetPerHour`, e.g. 1 per hour before
/// stage 2, but never below [minThreshold]. Without negatives (nothing to
/// measure the rate on) or with fewer than [wakeMinTemplates] positives the
/// result has `meetsTarget == false`. If the negatives do not constrain the
/// threshold, the [wakePositiveQuantile] quantile of the positives is used
/// instead of their minimum (outlier-robust); without any event at most
/// [wakeUnconstrainedMaxThreshold]; with events it never falls below the
/// lower of that cap and the quantile. [requireNegatives] `false`:
/// empty [negativeEvents] mean a measured quiet background, not a missing
/// one. A pure function.
WakeCalibration calibrateThreshold({
  required List<double> positiveScores,
  required List<double> negativeEvents,
  required double negativeHours,
  double targetPerHour = 1,
  double minThreshold = wakeMinThreshold,
  bool requireNegatives = true,
}) {
  if (negativeHours <= 0) throw ArgumentError.value(negativeHours, 'hours');
  final neg = [...negativeEvents]..sort();
  final pos = [...positiveScores]..sort();
  // Allowed number of negative events at/above the threshold.
  final allowed = (targetPerHour * negativeHours).floor();
  double threshold;
  if (neg.length <= allowed) {
    // Every negative may pass: a low quantile of the positives keeps the
    // recall high without letting one outlier decide.
    threshold = pos.isEmpty
        ? 0
        : pos[((pos.length - 1) * wakePositiveQuantile).floor()];
    // No event forces a higher threshold: cap it (a high quantile of
    // near-identical enrollment takes would cost recall, WP134).
    if (threshold > wakeUnconstrainedMaxThreshold) {
      threshold = wakeUnconstrainedMaxThreshold;
    }
  } else {
    // Exclude all but the [allowed] highest events.
    threshold = neg[neg.length - allowed - 1] + 1e-6;
    // A weak event (e.g. a quiet room with one 0.35 peak) says nothing about
    // false alarms by speech: do not fall below the capped quantile.
    if (pos.isNotEmpty) {
      final q = pos[((pos.length - 1) * wakePositiveQuantile).floor()];
      final floor = q < wakeUnconstrainedMaxThreshold
          ? q
          : wakeUnconstrainedMaxThreshold;
      if (threshold < floor) threshold = floor;
    }
  }
  if (threshold < minThreshold) threshold = minThreshold;
  final recall = pos.isEmpty
      ? 0.0
      : pos.where((p) => p >= threshold).length / pos.length;
  final fa = neg.where((n) => n >= threshold).length / negativeHours;
  return WakeCalibration(
    threshold: threshold,
    recall: recall,
    falseAlarmsPerHour: fa,
    meetsTarget:
        pos.length >= wakeMinTemplates &&
        (neg.isNotEmpty || !requireNegatives) &&
        fa <= targetPerHour &&
        recall > 0,
  );
}

/// Leave-one-out similarities of [templates]: each template against all
/// others (input of [calibrateThreshold] when only the templates exist).
List<double> leaveOneOutScores(
  List<Float32List> templates, {
  Float32List? mean,
}) => [
  for (var i = 0; i < templates.length; i++)
    bestSimilarity(templates[i], [
      for (var j = 0; j < templates.length; j++)
        if (j != i) templates[j],
    ], mean: mean),
];
