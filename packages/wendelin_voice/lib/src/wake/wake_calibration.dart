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

/// Picks the similarity threshold for personal templates.
///
/// [positiveScores] are the best template similarities of the speaker's own
/// utterances (use leave-one-out: never score an utterance against itself).
/// [negativeEvents] are the similarity peaks of background audio, **one per
/// event** (already separated by the refractory time) and [negativeHours]
/// the length of that background. The result is the lowest threshold with
/// `events at/above / negativeHours <= targetPerHour`, e.g. 1 per hour before
/// stage 2. A pure function.
WakeCalibration calibrateThreshold({
  required List<double> positiveScores,
  required List<double> negativeEvents,
  required double negativeHours,
  double targetPerHour = 1,
}) {
  if (negativeHours <= 0) throw ArgumentError.value(negativeHours, 'hours');
  final neg = [...negativeEvents]..sort();
  final pos = [...positiveScores]..sort();
  // Allowed number of negative events at/above the threshold.
  final allowed = (targetPerHour * negativeHours).floor();
  double threshold;
  if (neg.length <= allowed) {
    // Every negative may pass: the lowest positive keeps full recall.
    threshold = pos.isEmpty ? 0 : pos.first;
  } else {
    // Exclude all but the [allowed] highest events.
    threshold = neg[neg.length - allowed - 1] + 1e-6;
  }
  final recall = pos.isEmpty
      ? 0.0
      : pos.where((p) => p >= threshold).length / pos.length;
  final fa = neg.where((n) => n >= threshold).length / negativeHours;
  return WakeCalibration(
    threshold: threshold,
    recall: recall,
    falseAlarmsPerHour: fa,
    meetsTarget: fa <= targetPerHour && recall > 0,
  );
}

/// Leave-one-out similarities of [templates]: each template against all
/// others (input of [calibrateThreshold] when only the templates exist).
List<double> leaveOneOutScores(List<Float32List> templates) => [
  for (var i = 0; i < templates.length; i++)
    bestSimilarity(templates[i], [
      for (var j = 0; j < templates.length; j++)
        if (j != i) templates[j],
    ]),
];
