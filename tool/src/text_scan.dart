// Sucht feste deutsche Texte außerhalb der l10n-Fragmente (WP110, vorher ein
// Flutter-Test in app/test/l10n). Gescannt werden app/lib/{ui,agent,di,voice}.
// Bestand steht je Datei mit Anzahl in `tool/text_allowlist.yaml`; die Liste
// schrumpft nur (mehr Treffer als erlaubt ist rot, weniger ebenfalls, bis der
// Eintrag gesenkt ist).
import 'dart:io';

/// Verzeichnisse, in denen deutsche Texte nur mit Eintrag bleiben.
const textScanDirs = [
  'app/lib/ui',
  'app/lib/agent',
  'app/lib/di',
  'app/lib/voice',
];

final _german = RegExp(
  '[äöüßÄÖÜ]|\\b(der|die|das|und|nicht|Bitte|für|mit|wird|ist|kein|keine|'
  'Die|Das|Es|Ein|Eine|Kein|Du|Dein|Deine|zu|von|Ja|Nein)\\b',
);

// Deutsche Ein-Wort-Texte ohne Umlaut (Schaltflächen, Status).
final _germanWord = RegExp(
  '^(Abbrechen|Abmelden|Anmelden|Aktiv|Aktualisieren|Antwort|Aufnahme|'
  'Bearbeiten|Beenden|Bestätigen|Einstellungen|Entfernen|Fehler|'
  'Fertig|Hinweis|Hinzufügen|Inaktiv|Konto|Laden|Nachricht|Nein|Prüfen|'
  'Schließen|Senden|Speichern|Sprache|Starten|Stoppen|Suchen|Titel|Verbinden|'
  'Verbindung|Warten|Weiter|Wiederholen|Zurück|Zugang|Okay|Alle|Keine|'
  'Löschen|Öffnen|Erledigt|Offen|Fortfahren|Ablehnen|Erlauben|Zulassen)\$',
);

// Ein Textliteral ab 4 Zeichen (kein Bezeichner).
final _literal = RegExp('\'([^\'\\n]{4,})\'|"([^"\\n]{4,})"');

bool _skip(String line) {
  final s = line.trimLeft();
  return s.startsWith('//') ||
      s.startsWith('import ') ||
      s.startsWith('export ');
}

/// Treffer als `pfad:zeile: text` für alle .dart-Dateien unter [dir].
List<String> scanTexts(String dir) {
  final found = <String>[];
  final d = Directory(dir);
  if (!d.existsSync()) return found;
  final files = d.listSync(recursive: true).whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    if (!f.path.endsWith('.dart')) continue;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (_skip(lines[i])) continue;
      for (final m in _literal.allMatches(lines[i])) {
        final t = m[1] ?? m[2]!;
        if ((t.contains(' ') && _german.hasMatch(t)) ||
            _germanWord.hasMatch(t) ||
            RegExp('[äöüßÄÖÜ]').hasMatch(t)) {
          found.add('${f.path}:${i + 1}: $t');
        }
      }
    }
  }
  return found;
}

/// Treffer je Datei.
Map<String, int> countByFile(Iterable<String> findings) {
  final out = <String, int>{};
  for (final f in findings) {
    final p = f.substring(0, f.indexOf(':'));
    out[p] = (out[p] ?? 0) + 1;
  }
  return out;
}

/// Abweichungen zwischen [findings] und [allowed] (Datei → Anzahl).
List<String> compareTexts(Iterable<String> findings, Map<String, int> allowed) {
  final byFile = countByFile(findings);
  final msgs = <String>[];
  for (final MapEntry(:key, :value) in byFile.entries) {
    final a = allowed[key] ?? 0;
    if (value > a) {
      msgs.add(
        '$key: $value feste Texte (erlaubt $a). Sichtbare Texte gehören in '
        'app/lib/l10n/src/<bereich>/ (docs/ENGINEERING.md „Texte“):\n'
        '${findings.where((f) => f.startsWith('$key:')).map((f) => '    $f').join('\n')}',
      );
    }
  }
  for (final MapEntry(:key, :value) in allowed.entries) {
    final f = byFile[key] ?? 0;
    if (f < value) {
      msgs.add(
        '$key: nur noch $f feste Texte, Eintrag in tool/text_allowlist.yaml '
        '${f == 0 ? 'entfernen' : 'auf $f senken'}.',
      );
    }
  }
  return msgs;
}

/// Einträge, die gegenüber der Basis ([base], die Allowlist auf origin/main bzw. an der
/// Merge-Basis) neu sind oder höher stehen: die Liste darf nicht wachsen.
List<String> allowlistGrowth(
  Map<String, int> allowed,
  Map<String, int> base,
) => [
  for (final MapEntry(:key, :value) in allowed.entries)
    if (value > (base[key] ?? 0))
      'tool/text_allowlist.yaml: $key steht mit $value, Basis ${base[key] ?? 0} '
          '(die Liste darf nicht wachsen: Texte nach app/lib/l10n/src/<bereich>/ verschieben).',
];
