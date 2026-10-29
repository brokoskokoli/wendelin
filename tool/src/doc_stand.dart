// Stand-Zeile der Gerätetest-Anleitungen (docs/testing/m5/<wp>.md): zweite
// Zeile `> Stand: gültig | teilweise überholt (…) | überholt durch WPnn`.
final _standRe = RegExp(
  r'^> Stand: (gültig|teilweise überholt \(.+\)|überholt durch WP\d+\w*)$',
);

/// Stand-Zeile (zweite Zeile) von [text], oder null, wenn sie fehlt/ungültig ist.
String? standOf(String text) {
  final lines = text.split('\n');
  if (lines.length < 2 || !_standRe.hasMatch(lines[1])) return null;
  return lines[1].substring('> Stand: '.length);
}

/// Suffix für den Index: leer bei „gültig“, sonst der Stand ohne Klammertext.
String standSuffix(String text) {
  final s = standOf(text);
  if (s == null || s == 'gültig') return '';
  return s.startsWith('teilweise') ? ' (teilweise überholt)' : ' (überholt)';
}
