// Phonetische Schlüssel und Editierdistanz für den unscharfen Abgleich von
// Eigennamen (Notiztitel, Listennamen, Assistentenname) mit erkannter
// Sprache (WP33, B6). Reines Dart, ohne Abhängigkeiten.

import '../text/fold.dart';

/// Phonetic key of [text] for comparing names „by sound“: Kölner Phonetik
/// for German ([language] `de` or `null`), a simple Soundex variant without
/// length limit for other languages. Spaces, hyphens and case do not
/// matter; „Wandel Intest“ and „Wendelin-Test“ have the same key.
String phoneticKey(String text, {String? language}) =>
    language == null || language == 'de'
    ? colognePhonetic(text)
    : simplePhonetic(text);

/// Kölner Phonetik (Postel 1969) of [text] as digit string, computed on
/// [foldFlat] (the whole text counts as one word).
String colognePhonetic(String text) {
  final s = foldFlat(text);
  final raw = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final prev = i > 0 ? s[i - 1] : '';
    final next = i + 1 < s.length ? s[i + 1] : '';
    raw.write(switch (c) {
      'a' || 'e' || 'i' || 'j' || 'o' || 'u' || 'y' => '0',
      'h' => '',
      'b' => '1',
      'p' => next == 'h' ? '3' : '1',
      'd' || 't' => 'csz'.contains(next) && next.isNotEmpty ? '8' : '2',
      'f' || 'v' || 'w' => '3',
      'g' || 'k' || 'q' => '4',
      'c' => _cologneC(i, prev, next),
      'x' => 'ckq'.contains(prev) && prev.isNotEmpty ? '8' : '48',
      'l' => '5',
      'm' || 'n' => '6',
      'r' => '7',
      's' || 'z' => '8',
      // Digits and other letters (non-Latin) stand for themselves.
      _ => _isDigit(c) ? c : '',
    });
  }
  return _squeeze(raw.toString());
}

String _cologneC(int i, String prev, String next) {
  if (next.isEmpty) return '8';
  if (i == 0) return 'ahkloqrux'.contains(next) ? '4' : '8';
  if ('sz'.contains(prev) && prev.isNotEmpty) return '8';
  return 'ahkoqux'.contains(next) ? '4' : '8';
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

/// Collapses repeated codes and drops `0` (vowels) except at the start.
String _squeeze(String raw) {
  final b = StringBuffer();
  var last = '';
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (c == last) continue;
    last = c;
    if (c == '0' && b.isNotEmpty) continue;
    b.write(c);
  }
  return b.toString();
}

/// Simple Soundex-like key for French and English: consonant classes,
/// vowels dropped (except a leading one, as `0`), repeats collapsed, no
/// length limit; `ph` counts as `f`.
String simplePhonetic(String text) {
  final s = foldFlat(text).replaceAll('ph', 'f');
  final raw = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    raw.write(switch (c) {
      'b' || 'f' || 'p' || 'v' => '1',
      'c' || 'g' || 'j' || 'k' || 'q' || 's' || 'x' || 'z' => '2',
      'd' || 't' => '3',
      'l' => '4',
      'm' || 'n' => '5',
      'r' => '6',
      'a' || 'e' || 'i' || 'o' || 'u' || 'y' => '0',
      // h and w do not separate equal codes (Soundex rule).
      'h' || 'w' => '',
      _ => _isDigit(c) ? c : '',
    });
  }
  return _squeeze(raw.toString());
}

/// Levenshtein distance of [a] and [b] (UTF-16 code units).
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}
