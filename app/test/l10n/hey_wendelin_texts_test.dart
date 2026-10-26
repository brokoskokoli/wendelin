import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// WP156: Wo „Wendelin“ als zu sprechendes Wort in Anführungszeichen steht,
/// muss „Hey“ davor stehen (Nutzer sollen „Hey Wendelin“ sagen). Der App-Name
/// ohne Anführungszeichen („Wendelin hört mit“) ist davon nicht betroffen.
///
/// Allowlist: Schlüssel, in denen ein Anführungszeichen-Wendelin etwas
/// anderes meint als das gesprochene Wort. Derzeit leer; jeder Eintrag
/// braucht eine Begründung.
const _allow = <String, String>{};

// Öffnendes Anführungszeichen („ “ " « ' ‚ ‘ ») oder schließendes direkt am
// Wort; davor optional „Hey “.
final _quoted = RegExp(
  r'''(?:[„“"«‚‘'»]\s?)(Hey\s+|Hei\s+|Hej\s+|Hay\s+)?Wendelin(?:\s?[“”"»«‘’'])''',
  caseSensitive: false,
);

List<String> offenders(String key, String value) {
  if (_allow.containsKey(key)) return const [];
  return [
    for (final m in _quoted.allMatches(value))
      if (m.group(1) == null) '$key: ${m.group(0)}',
  ];
}

void main() {
  test('Wendelin in Anführungszeichen steht nur als „Hey Wendelin“', () {
    final files = Directory('lib/l10n/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.arb'))
        .toList();
    expect(files, isNotEmpty);
    final bad = <String>[];
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final e in json.entries) {
        if (e.key.startsWith('@') || e.value is! String) continue;
        bad.addAll(offenders('${f.path}#${e.key}', e.value as String));
      }
    }
    expect(bad, isEmpty, reason: 'Wendelin ohne „Hey“ in Anführungszeichen');
  });

  test('Muster erkennt alle Anführungszeichen-Arten (Negativtest)', () {
    for (final s in [
      'Sag „Wendelin“.',
      'Say “Wendelin”.',
      'Say "Wendelin".',
      'Dites « Wendelin ».',
      'Dites «Wendelin».',
    ]) {
      expect(offenders('k', s), isNotEmpty, reason: s);
    }
    for (final s in [
      'Sag „Hey Wendelin“.',
      'Say “Hey Wendelin”.',
      'Dites « Hey Wendelin ».',
      'Wendelin hört mit.',
      'Android → Apps → Wendelin',
    ]) {
      expect(offenders('k', s), isEmpty, reason: s);
    }
  });
}
