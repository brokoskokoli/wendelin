// Text-Faltung für unscharfe Vergleiche von Namen (WP33). Einzige Stelle
// dieser Art: Listen-, Obsidian- und Routing-Abgleich nutzen sie (WP36 c).
// Ausnahme: Tool-Namen in `wendelin_mcp` (ä→ae, siehe dort).

/// Folds [s] for comparing names: lower case; diacritics removed (ä→a,
/// é→e, ç→c, ñ→n); ligatures and special letters spelled out (ß→ss,
/// æ→ae, œ→oe, ø→o); every run of other characters (spaces, hyphens,
/// underscores, punctuation, symbols) becomes one space; trimmed.
/// Letters of other scripts and digits stay. „Wendelin-Test“ →
/// `wendelin test`, „Größe_Ärger!“ → `grosse arger`.
///
/// With [basicOnly] the special letters ã å õ ø ý ÿ æ œ stay as they are
/// (the behaviour of list and note matching before WP36 c; their callers
/// read `ae/oe/ue` as umlauts afterwards, see `foldText`).
String foldForMatch(String s, {bool basicOnly = false}) {
  final b = StringBuffer();
  var gap = false;
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final folded = (basicOnly ? _basic[c] : _letters[c]) ?? c;
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

/// Folds one lower-case character [c] with the table of [foldForMatch]
/// (no separator handling); used where positions in the source text must
/// be tracked (routing).
String foldLetter(String c) => _letters[c] ?? c;

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
  'ý': 'y',
  'ÿ': 'y',
  'ç': 'c',
  'ñ': 'n',
  'ß': 'ss',
  'œ': 'oe',
  'æ': 'ae',
};

const _extended = {'ã', 'å', 'õ', 'ø', 'ý', 'ÿ', 'æ', 'œ'};

final _basic = {
  for (final e in _letters.entries)
    if (!_extended.contains(e.key)) e.key: e.value,
};
