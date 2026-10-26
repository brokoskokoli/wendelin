// Ratsche (WP109): eine Baseline darf nur schrumpfen. Neue Treffer und
// Treffer über dem Wert sind rot; ein Wert, der nicht mehr erreicht wird
// (oder ein veralteter Eintrag), ist ebenfalls rot, bis die Baseline gesenkt
// ist. `--update-baseline` senkt oder entfernt, erhöht aber nie.

/// Liest `<schlüssel>: <zahl>` (Zeilen mit `#` am Anfang sind Kommentare).
/// Schlüssel dürfen `#` und `:` enthalten; die Zahl steht nach dem letzten `:`.
Map<String, int> parseBaseline(String text) {
  final out = <String, int>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final i = line.lastIndexOf(':');
    if (i < 0) continue;
    final n = int.tryParse(line.substring(i + 1).trim());
    if (n != null) out[line.substring(0, i).trim()] = n;
  }
  return out;
}

/// Vergleicht [current] mit [baseline]. [what] benennt die Art („Größenwarnung“,
/// „ignore-Budget“), [file] die Datei und [fix] den Befehl zum Senken.
List<String> ratchetErrors(
  Map<String, int> current,
  Map<String, int> baseline, {
  required String what,
  required String file,
  required String fix,
}) {
  final errors = <String>[];
  for (final MapEntry(:key, :value) in current.entries) {
    final b = baseline[key];
    if (b == null) {
      errors.add(
        '$key: neu ($what, $value). Beheben, nicht in $file eintragen '
        '(die Baseline darf nur schrumpfen).',
      );
    } else if (value > b) {
      errors.add('$key: $what gewachsen auf $value (Baseline $b).');
    } else if (value < b) {
      errors.add(
        '$key: nur noch $value ($what), Baseline $b in $file senken ($fix).',
      );
    }
  }
  for (final MapEntry(:key, :value) in baseline.entries) {
    if (!current.containsKey(key)) {
      errors.add(
        '$key: $what nicht mehr vorhanden, Eintrag ($value) aus $file '
        'entfernen ($fix).',
      );
    }
  }
  return errors;
}

/// Neue Baseline für `--update-baseline`: nur senken oder entfernen, nie
/// erhöhen und nie neue Schlüssel aufnehmen.
Map<String, int> lowerBaseline(
  Map<String, int> current,
  Map<String, int> baseline,
) {
  final out = <String, int>{};
  for (final MapEntry(:key, :value) in baseline.entries) {
    final c = current[key];
    if (c == null) continue;
    out[key] = c < value ? c : value;
  }
  return out;
}

/// Schreibt die Baseline (Kopfzeilen [header], Einträge sortiert).
String renderBaseline(String header, Map<String, int> map) {
  final keys = map.keys.toList()..sort(naturalCompare);
  if (keys.isEmpty) return '$header\n';
  return '$header\n${[for (final k in keys) '$k: ${map[k]}'].join('\n')}\n';
}

/// Der Kopf einer vorhandenen Datei: alle führenden Kommentarzeilen.
String headerOf(String text) {
  final lines = <String>[];
  for (final l in text.split('\n')) {
    if (!l.startsWith('#')) break;
    lines.add(l);
  }
  return lines.join('\n');
}

/// Natürliche Sortierung: Zahlenfolgen zählen numerisch (`K5` vor `K100`).
int naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(a).map((m) => m[0]!).toList();
  final pb = re.allMatches(b).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
