// Text-Faltung für unscharfe Vergleiche von Namen (WP33; WP36 Teil c stellt
// Listen-, Obsidian- und Routing-Abgleich darauf um).

/// Folds [s] for comparing names: lower case; diacritics removed (ä→a,
/// é→e, ç→c, ñ→n); ligatures and special letters spelled out (ß→ss,
/// æ→ae, œ→oe, ø→o); every run of other characters (spaces, hyphens,
/// underscores, punctuation, symbols) becomes one space; trimmed.
/// Letters of other scripts and digits stay. „Wendelin-Test“ →
/// `wendelin test`, „Größe_Ärger!“ → `grosse arger`.
String foldForMatch(String s) {
  final b = StringBuffer();
  var gap = false;
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final folded = _letters[c] ?? c;
    if (_letterOrDigit.hasMatch(folded)) {
      if (gap && b.isNotEmpty) b.write(' ');
      gap = false;
      b.write(folded);
    } else {
      gap = true;
    }
  }
  return b.toString();
}

/// [foldForMatch] without spaces: „Wandel Intest“ → `wandelintest`
/// (used where word boundaries from speech recognition are unreliable).
String foldFlat(String s) => foldForMatch(s).replaceAll(' ', '');

final _letterOrDigit = RegExp(r'^[\p{L}\p{N}]+$', unicode: true);

const _letters = {
  'ä': 'a',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'ö': 'o',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'ü': 'u',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ÿ': 'y',
  'ç': 'c',
  'ñ': 'n',
  'ß': 'ss',
  'œ': 'oe',
  'æ': 'ae',
};
