// Gate-Schritt: keine flackernden Wartemuster in Tests (siehe
// tool/src/flaky_scan.dart). Bestand: tool/flaky_allowlist.yaml.
//
//   dart run tool/check_flaky.dart [--list]   (--list schreibt die Liste)
import 'dart:io';

import 'src/flaky_scan.dart';

void main(List<String> args) {
  final found = scanFlaky(testFiles());
  if (args.contains('--list')) {
    for (final e in found.entries) {
      stdout.writeln('${e.key}: ${e.value}');
    }
    return;
  }
  final list = File('tool/flaky_allowlist.yaml');
  final allowed = list.existsSync()
      ? parseFlakyAllowlist(list.readAsStringSync())
      : <String, int>{};
  final msgs = compareFlaky(found, allowed);
  if (msgs.isEmpty) {
    stdout.writeln(
      'check_flaky: ok (${found.length} Dateien auf der Ausnahmeliste)',
    );
    return;
  }
  msgs.forEach(stderr.writeln);
  exitCode = 1;
}
