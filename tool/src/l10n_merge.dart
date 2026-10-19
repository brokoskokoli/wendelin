// Kern von tool/l10n_merge.dart: Bereichszuordnung, Zusammenführen der
// ARB-Fragmente und Konsistenzprüfung. Rein, ohne Dateizugriff.
import 'dart:convert';

const langs = ['de', 'en', 'fr'];

/// Bereich je Schlüsselpräfix (führende Kleinbuchstaben/Ziffern vor dem ersten
/// Großbuchstaben). Unbekannte Präfixe landen in `common`. Eine neue
/// Integration trägt hier ihren eigenen Bereich ein.
const prefixAreas = <String, String>{
  'att': 'attest',
  'gpu': 'attest',
  'stage': 'attest',
  'shield': 'attest',
  'check': 'attest',
  'wake': 'wake',
  'barge': 'wake',
  'mic': 'wake',
  'voice': 'voice',
  'model': 'voice',
  'language': 'voice',
  'mcp': 'mcp',
  'tool': 'mcp',
  'http': 'http',
  'routing': 'routing',
  'cond': 'routing',
  'rule': 'routing',
  'provider': 'provider',
  'providers': 'provider',
  'costs': 'provider',
  'area': 'provider',
  'target': 'provider',
  'integration': 'integrations',
  'integrations': 'integrations',
  'coming': 'integrations',
  'ha': 'ha',
  'obsidian': 'obsidian',
  'obs': 'obsidian',
  'spotify': 'spotify',
  'bring': 'bring',
  'lists': 'lists',
  'weather': 'weather',
  'web': 'websearch',
  'assistant': 'assistant',
  'agent': 'assistant',
  'reducer': 'assistant',
  'conversation': 'assistant',
  'main': 'main',
  'conf': 'main',
  'overlay': 'main',
  'switch': 'main',
  'private': 'main',
  'privacy': 'privacy',
  'audit': 'privacy',
  'memory': 'privacy',
  'onboarding': 'onboarding',
  'battery': 'device',
  'dev': 'device',
};

final _prefix = RegExp(r'^[a-z][a-z0-9]*');

/// Bereich eines Schlüssels (ohne führendes `@`).
String areaFor(String key) {
  final p = _prefix.stringMatch(key.startsWith('@') ? key.substring(1) : key);
  return prefixAreas[p] ?? 'common';
}

/// Fragmente: Bereich → Sprache → Eintragsliste (Schlüssel und `@`-Metadaten).
typedef Fragments = Map<String, Map<String, Map<String, Object?>>>;

String _base(String k) => k.startsWith('@') ? k.substring(1) : k;

int _order(String a, String b) {
  final c = _base(a).compareTo(_base(b));
  if (c != 0) return c;
  return a.startsWith('@') == b.startsWith('@')
      ? 0
      : (a.startsWith('@') ? 1 : -1);
}

/// Fragment-Inhalt in kanonischer Form: Schlüssel alphabetisch, `@key` folgt
/// direkt auf `key`.
Map<String, Object?> canonical(Map<String, Object?> entries) => {
  for (final k in entries.keys.toList()..sort(_order)) k: entries[k],
};

/// Gesamt-ARB einer Sprache: `@@locale`, dann Bereiche alphabetisch.
Map<String, Object?> mergeLang(Fragments fr, String lang) {
  final out = <String, Object?>{'@@locale': lang};
  for (final area in fr.keys.toList()..sort()) {
    out.addAll(canonical(fr[area]![lang] ?? const {}));
  }
  return out;
}

String render(Map<String, Object?> arb) =>
    '${const JsonEncoder.withIndent('  ').convert(arb)}\n';

/// Konsistenzprobleme der Fragmente (leer = in Ordnung).
List<String> problems(Fragments fr) {
  final out = <String>[];
  final keys = <String, Set<String>>{for (final l in langs) l: {}};
  for (final lang in langs) {
    final owner = <String, String>{};
    for (final area in fr.keys.toList()..sort()) {
      for (final k in fr[area]![lang]?.keys ?? const <String>[]) {
        if (k.startsWith('@@')) {
          out.add('$area/$lang: $k gehört nicht in ein Fragment');
          continue;
        }
        final prev = owner[k];
        if (prev != null && prev != area) {
          out.add('doppelter Schlüssel $k ($lang): in $prev und $area');
        }
        owner[k] = area;
        if (!k.startsWith('@')) keys[lang]!.add(k);
      }
      for (final k in fr[area]![lang]?.keys ?? const <String>[]) {
        if (k.startsWith('@') &&
            !k.startsWith('@@') &&
            !(fr[area]![lang]!.containsKey(_base(k)))) {
          out.add('$area/$lang: Metadaten $k ohne Schlüssel');
        }
      }
    }
  }
  for (final lang in langs.skip(1)) {
    for (final k in keys['de']!.difference(keys[lang]!)) {
      out.add('Schlüssel $k fehlt in $lang');
    }
    for (final k in keys[lang]!.difference(keys['de']!)) {
      out.add('Schlüssel $k fehlt in de');
    }
  }
  return out..sort();
}

/// Verteilt Einträge der Gesamt-ARB (`arb`), die in keinem Fragment stehen,
/// auf Fragmente. `area` erzwingt einen Bereich, sonst gilt [areaFor].
/// Liefert die übernommenen Schlüssel.
Set<String> adopt(
  Fragments fr,
  String lang,
  Map<String, Object?> arb, {
  String? area,
}) {
  final known = {
    for (final a in fr.values)
      for (final k in a[lang]?.keys ?? const <String>[]) _base(k),
  };
  final taken = <String>{};
  for (final k in arb.keys) {
    if (k.startsWith('@@') || known.contains(_base(k))) continue;
    final a = area ?? areaFor(k);
    fr.putIfAbsent(a, () => {})[lang] ??= {};
    fr[a]![lang]![k] = arb[k];
    taken.add(_base(k));
  }
  return taken;
}
