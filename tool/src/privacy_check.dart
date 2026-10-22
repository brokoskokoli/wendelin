// Datenschutz-Prüfung für das öffentliche Repo (WP127): keine lokalen
// Pfade mit Benutzername und keine Begriffe aus einer Liste außerhalb des
// Repos (`~/.config/wendelin/forbidden-terms.txt`, eine Zeile je Begriff).
import 'dart:io';

/// Platzhalter und Systemnutzer, die vorkommen dürfen (`/home/x/…` in Tests,
/// `/home/root/` in den TEE-Attestierungen, `runner` in der CI).
const _placeholderUsers = {
  'x',
  'u',
  'user',
  'name',
  'me',
  'runner',
  'you',
  'root',
};

final _homePath = RegExp(r'(?:/Users|/home)/([A-Za-z0-9._-]+)/');
final _claudeTmp = RegExp(
  r'/private/tmp/'
  r'claude-',
);

/// Standardort der Begriffsliste (nie im Repo); `WENDELIN_TERMS_FILE` überschreibt ihn.
String termsFilePath() =>
    Platform.environment['WENDELIN_TERMS_FILE'] ??
    '${Platform.environment['HOME'] ?? ''}/.config/wendelin/forbidden-terms.txt';

/// Liest die Begriffe (klein geschrieben); `null`, wenn die Datei fehlt.
List<String>? loadTerms(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  return [
    for (final l in f.readAsLinesSync())
      if (l.trim().isNotEmpty && !l.trim().startsWith('#'))
        l.trim().toLowerCase(),
  ];
}

/// Grund eines Treffers in [line] oder `null`. Der Begriff selbst wird nie
/// zurückgegeben, damit keine Meldung die Liste verrät.
String? leak(String line, List<String>? terms) {
  for (final m in _homePath.allMatches(line)) {
    if (!_placeholderUsers.contains(m.group(1))) return 'lokaler Pfad';
  }
  if (_claudeTmp.hasMatch(line)) return 'lokaler Scratchpad-Pfad';
  if (terms != null) {
    final low = line.toLowerCase();
    for (final t in terms) {
      if (low.contains(t)) return 'verbotener Begriff';
    }
  }
  return null;
}

/// Treffer als `datei:zeile (Grund)` für den Text [text] der Datei [path].
List<String> scanText(String path, String text, List<String>? terms) => [
  for (final (i, l) in text.split('\n').indexed)
    if (leak(l, terms) case final why?) '$path:${i + 1} ($why)',
];

/// Treffer in den hinzugefügten Zeilen eines `git diff -U0`.
List<String> scanDiff(String diff, List<String>? terms) {
  final out = <String>[];
  String? file;
  var line = 0;
  for (final l in diff.split('\n')) {
    if (l.startsWith('+++ ')) {
      file = l == '+++ /dev/null'
          ? null
          : l.substring(l.startsWith('+++ b/') ? 6 : 4);
    } else if (l.startsWith('@@')) {
      final m = RegExp(r'\+(\d+)').firstMatch(l);
      line = m == null ? 0 : int.parse(m.group(1)!);
    } else if (l.startsWith('+') && file != null) {
      if (leak(l.substring(1), terms) case final why?) {
        out.add('$file:$line ($why)');
      }
      line++;
    }
  }
  return out;
}

/// Prüft alle versionierten Textdateien (oder nur die hinzugefügten Zeilen
/// des Index mit [staged]). Gibt den Exit-Code zurück.
int runPrivacyCheck({bool staged = false, String? termsPath}) {
  final terms = loadTerms(termsPath ?? termsFilePath());
  final hits = <String>[];
  if (staged) {
    final r = Process.runSync('git', [
      '-c',
      'core.quotepath=off',
      'diff',
      '--cached',
      '-U0',
      '--no-color',
      '--no-ext-diff',
    ]);
    hits.addAll(scanDiff(r.stdout as String, terms));
  } else {
    final r = Process.runSync('git', [
      '-c',
      'core.quotepath=off',
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
    ]);
    for (final path in (r.stdout as String).split('\n')) {
      final f = File(path);
      if (path.isEmpty || !f.existsSync()) continue;
      String text;
      try {
        text = f.readAsStringSync();
      } on FileSystemException {
        continue; // Binärdatei
      }
      hits.addAll(scanText(path, text, terms));
    }
  }
  if (terms == null) {
    stderr.writeln(
      'check_privacy: keine Begriffsliste (${staged ? 'Hook' : 'Gate'}), '
      'nur Pfadmuster geprüft',
    );
  }
  if (hits.isEmpty) {
    stdout.writeln('check_privacy: ok');
    return 0;
  }
  hits.forEach(stderr.writeln);
  stderr.writeln(
    'check_privacy: ${hits.length} Treffer (Regel: docs/agents/common.md → Öffentliches Repo)',
  );
  return 1;
}
