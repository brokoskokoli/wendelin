import 'package:wendelin_voice/wendelin_voice.dart';

import '../../voice/voice_log.dart';
import 'wake_stage2_gap.dart';

/// The `wake-alive` line (counters only, no content): candidates and hits
/// per hour, the cost of the recognizer fallback (WP171) and, in developer
/// mode ([shadow]), the shadow detector's compute time per window since the
/// last line (which starts the next interval).
void logWakeAlive(
  WakeWordStats stats,
  WakeFallbackStats fb, {
  required bool shadow,
}) {
  String perHour(int n) =>
      (stats.runtime.inSeconds < 60
              ? 0.0
              : n * Duration.microsecondsPerHour / stats.runtime.inMicroseconds)
          .toStringAsFixed(1);
  final cost = fb.shadow;
  voiceLog('wake-alive', {
    'cand': stats.candidates,
    'ok': stats.confirmed,
    'candPerH': stats.candidatesPerHour.toStringAsFixed(1),
    'okPerH': stats.confirmedPerHour.toStringAsFixed(1),
    'min': stats.runtime.inMinutes,
    // WP171: what the recognizer fallback costs (loads stay far below
    // checks while the model stays warm for `idleRelease`).
    'fbLoads': fb.loads,
    'fbChecks': fb.checks,
    'fbLoadsPerH': perHour(fb.loads),
    'fbChecksPerH': perHour(fb.checks),
    if (shadow && cost.count > 0) ...{
      'shMeanUs': cost.meanUs,
      'shMaxUs': cost.maxUs,
      'shN': cost.count,
    },
  });
  cost.reset();
}
