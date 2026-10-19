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
  final base = _baseAllowlist();
  final inCi = Platform.environment['CI'] == 'true';
  final msgs = [
    ...compareTexts(found, allowed),
    if (inCi && !_hasBase())
      'check_texts: keine Basis (origin/main) zum Vergleich der Allowlist; '
          'im CI mit fetch-depth: 0 auschecken.'
    else
      ...allowlistGrowth(allowed, base ?? allowed),
  ];
  if (msgs.isEmpty) {
    stdout.writeln(
      'check_texts: ok (${allowed.length} Dateien auf der Ausnahmeliste)',
    );
    return;
  }
  msgs.forEach(stderr.writeln);
  exitCode = 1;
}

/// Wahr, wenn origin/main auflösbar ist (Datei dort darf noch fehlen: Ersteinführung).
bool _hasBase() {
  try {
    return Process.runSync('git', [
          'rev-parse',
          '--verify',
          '-q',
          'origin/main',
        ]).exitCode ==
        0;
  } on ProcessException {
    return false;
  }
}

/// Allowlist der Basis (Merge-Basis mit origin/main, sonst origin/main) aus git;
/// null, wenn es keine gibt (kein origin/main, Datei dort noch nicht vorhanden).
Map<String, int>? _baseAllowlist() {
  String? git(List<String> a) {
    try {
      final r = Process.runSync('git', a);
      return r.exitCode == 0 ? r.stdout as String : null;
    } on ProcessException {
      return null;
    }
  }

  final mb = git(['merge-base', 'HEAD', 'origin/main'])?.trim();
  final text = git([
    'show',
    '${mb == null || mb.isEmpty ? 'origin/main' : mb}:tool/text_allowlist.yaml',
  ]);
  return text == null ? null : parseFlakyAllowlist(text);
}
