// Prüfung des Einlern-Logs der Wake-Gerätetests (WP151). Reines Dart, damit
// `test/voice/enroll_log_check_test.dart` die Regel ohne Gerät prüft.

import 'barge_log.dart';

/// A rejected recording (`enroll-check ... ok=false`) or a dropped outlier
/// (`enroll-outlier`) in [lines]: the enrollment then reaches its target with
/// a repeated last file, which the screen does not show. Returns the first
/// problem or `null`; also a problem if no `enroll-check` was logged at all.
String? enrollLogProblem(List<String> lines) {
  var checks = 0;
  for (final l in lines) {
    if (isLogEvent(l, 'enroll-check') && logField(l, 'ok') == 'false') {
      return 'Aufnahme abgelehnt: $l';
    }
    if (isLogEvent(l, 'enroll-check')) checks++;
    if (isLogEvent(l, 'enroll-outlier')) return 'Ausreißer verworfen: $l';
  }
  return checks == 0 ? 'kein enroll-check im Log' : null;
}
