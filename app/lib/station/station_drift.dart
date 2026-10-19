import 'dart:ui';

/// Slow shifts of the content against burn-in: the position changes every
/// [stationDriftStep] along a small loop (at most [stationDriftReach] logical
/// pixels).
const stationDriftStep = Duration(minutes: 5);

/// Largest shift in logical pixels, per axis.
const stationDriftReach = 14.0;

const _loop = <Offset>[
  Offset(0, 0),
  Offset(stationDriftReach, 0),
  Offset(stationDriftReach, stationDriftReach),
  Offset(0, stationDriftReach),
  Offset(-stationDriftReach, stationDriftReach),
  Offset(-stationDriftReach, 0),
  Offset(-stationDriftReach, -stationDriftReach),
  Offset(0, -stationDriftReach),
];

/// Where the content sits at [now].
Offset stationDrift(DateTime now) {
  final step = now.millisecondsSinceEpoch ~/ stationDriftStep.inMilliseconds;
  return _loop[step % _loop.length];
}
