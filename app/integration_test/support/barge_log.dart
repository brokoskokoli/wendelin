// Prüfung der Barge-in-Diagnosezeilen (WP113, K84) aus dem Mikrofon-Log des
// Overlays. Reines Dart, damit `test/voice/barge_log_check_test.dart` die
// Regeln ohne Gerät prüft.

/// Value of `key=` in the voice-log [line] (`null` if missing).
String? logField(String line, String key) {
  final m = RegExp('(?:^|\\s)${RegExp.escape(key)}=(\\S+)').firstMatch(line);
  return m?.group(1);
}

/// Whether [line] is the voice-log event [event].
bool isLogEvent(String line, String event) =>
    line.contains('Wendelin/voice: $event ');

/// The `barge-hit kind=` that follows a verdict.
const bargeHitOfVerdict = {'stop': 'keyword-stop', 'wake': 'keyword-wake'};

/// Checks the two-stage barge-in (K84) in [lines]: `barge-config` has
/// `verify=true`, every `barge-hit` is preceded by a `barge-cand` and by a
/// `barge-verify` whose result belongs to it (no hit after `no`, `echo` or
/// `skip`), and at least one hit of [hitKind] happened (when given).
/// Returns the first problem or `null`.
String? bargeLogProblem(List<String> lines, {String? hitKind}) {
  final config = lines.where((l) => isLogEvent(l, 'barge-config'));
  if (config.isEmpty) return 'kein barge-config';
  if (config.any((l) => logField(l, 'verify') != 'true')) {
    return 'barge-config ohne verify=true';
  }
  var cand = false;
  String? verdict;
  var hits = 0, wanted = 0;
  for (final l in lines) {
    if (isLogEvent(l, 'barge-cand')) {
      cand = true;
    } else if (isLogEvent(l, 'barge-verify')) {
      verdict = logField(l, 'result');
    } else if (isLogEvent(l, 'barge-hit')) {
      hits++;
      final kind = logField(l, 'kind');
      if (!cand) return 'barge-hit ohne barge-cand: $l';
      if (bargeHitOfVerdict[verdict] != kind) {
        return 'barge-hit kind=$kind ohne passendes barge-verify '
            '(zuletzt result=$verdict)';
      }
      if (kind == hitKind) wanted++;
      // One verdict, one hit.
      verdict = null;
      cand = false;
    }
  }
  if (hits == 0) return 'kein barge-hit';
  if (hitKind != null && wanted == 0) return 'kein barge-hit kind=$hitKind';
  return null;
}
