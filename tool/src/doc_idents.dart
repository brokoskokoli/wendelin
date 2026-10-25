// Bezeichner-Check für die Architekturdoku (WP147): CamelCase-Bezeichner in
// Backticks unter `docs/architecture/` (ohne `generated/`) müssen irgendwo im
// Code (Dart, Kotlin, Rust) vorkommen, sonst beschreibt die Doku etwas, das es
// nicht (mehr) gibt. Bestand steht in `tool/doc_ident_allowlist.yaml`
// (Ratsche: nur abbauen).

final _span = RegExp(r'`([^`\n]+)`');
final _camel = RegExp(r'^[A-Za-z][A-Za-z0-9]*[a-z0-9][A-Z][A-Za-z0-9]*$');

/// Bezeichner (ohne Klammern am Ende) der Backtick-Spannen in [text]; Zeilen
/// in Codeblöcken (```) zählen nicht.
Iterable<String> camelIdents(String text) sync* {
  var fenced = false;
  for (final line in text.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    for (final m in _span.allMatches(line)) {
      // `Typ.methode(arg)` → `Typ`, `methode`; andere Spannen (Pfade, Befehle,
      // Ausdrücke mit Leerzeichen) sind keine Bezeichner.
      final s = m[1]!.trim().replaceFirst(RegExp(r'\(.*\)$'), '');
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)*$')
          .hasMatch(s)) {
        continue;
      }
      for (final part in s.split('.')) {
        if (_camel.hasMatch(part)) yield part;
      }
    }
  }
}

/// Alle Bezeichner-Wörter aus [code] (Quelltext).
void addCodeWords(String code, Set<String> into) {
  for (final m in RegExp(r'[A-Za-z_][A-Za-z0-9_]*').allMatches(code)) {
    into.add(m[0]!);
  }
}

/// Unbekannte Bezeichner je Dokument: Schlüssel `<doc>#<bezeichner>`, Wert =
/// Anzahl der Vorkommen. [docs] ist Pfad → Text, [code] die Wörter des Codes.
Map<String, int> unknownIdents(Map<String, String> docs, Set<String> code) {
  final out = <String, int>{};
  for (final e in docs.entries) {
    for (final id in camelIdents(e.value)) {
      if (!code.contains(id))
        out['${e.key}#$id'] = (out['${e.key}#$id'] ?? 0) + 1;
    }
  }
  return out;
}
