// Gate-Schritt: keine festen deutschen Texte außerhalb l10n (siehe
// tool/src/text_scan.dart). Bestand: tool/text_allowlist.yaml (nur abbauen).
//
//   dart run tool/check_texts.dart [--list]   (--list schreibt die Allowlist)
import 'dart:io';

import 'src/flaky_scan.dart' show parseFlakyAllowlist;
import 'src/text_scan.dart';

void main(List<String> args) {
  final found = [for (final d in textScanDirs) ...scanTexts(d)];
  if (args.contains('--list')) {
    for (final e in countByFile(found).entries) {
      stdout.writeln('${e.key}: ${e.value}');
    }
    return;
  }
  final list = File('tool/text_allowlist.yaml');
  final allowed = list.existsSync()
      ? parseFlakyAllowlist(list.readAsStringSync())
      : <String, int>{};
  final msgs = compareTexts(found, allowed);
  if (msgs.isEmpty) {
    stdout.writeln(
      'check_texts: ok (${allowed.length} Dateien auf der Ausnahmeliste)',
    );
    return;
  }
  msgs.forEach(stderr.writeln);
  exitCode = 1;
}
