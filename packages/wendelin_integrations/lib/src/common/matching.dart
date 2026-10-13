// Unscharfer Abgleich von Listennamen und Einträgen (de/en).

/// Lower case, umlauts folded (ä→a, ß→ss), punctuation and whitespace
/// collapsed to single spaces.
String normalizeText(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final r in lower.runes) {
    final c = String.fromCharCode(r);
    b.write(switch (c) {
      'ä' || 'à' || 'á' || 'â' => 'a',
      'ö' || 'ò' || 'ó' || 'ô' => 'o',
      'ü' || 'ù' || 'ú' || 'û' => 'u',
      'é' || 'è' || 'ê' || 'ë' => 'e',
      'í' || 'ì' || 'î' || 'ï' => 'i',
      'ç' => 'c',
      'ñ' => 'n',
      'ß' => 'ss',
      _ => c,
    });
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

const _fillers = {
  'die',
  'der',
  'das',
  'meine',
  'meiner',
  'mein',
  'unsere',
  'liste',
  'list',
  'the',
  'my',
  'our',
};

/// Reduces a single normalized word to a rough stem: compound suffix
/// `liste`/`list`, Fugen-s, German and English plural endings.
String stemWord(String w) {
  var s = w;
  for (final suffix in ['liste', 'listen', 'list', 'lists']) {
    if (s.length > suffix.length + 2 && s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length);
      if (s.endsWith('s') && s.length > 4) s = s.substring(0, s.length - 1);
      break;
    }
  }
  // „grocery“/„groceries“: y wie i behandeln.
  if (s.endsWith('y')) s = '${s.substring(0, s.length - 1)}i';
  for (final ending in ['en', 'er', 'es', 'n', 'e', 's']) {
    if (s.length > ending.length + 3 && s.endsWith(ending)) {
      return s.substring(0, s.length - ending.length);
    }
  }
  return s;
}

/// [normalizeText] plus `ae/oe/ue` read as umlauts („Buecher“ = „Bücher“);
/// used everywhere names or items are compared.
String foldText(String s) =>
    normalizeText(s)
        .replaceAll('ae', 'a')
        .replaceAll('oe', 'o')
        .replaceAll('ue', 'u');

final class _Key {
  _Key(String s) {
    final folded = foldText(s);
    flat = folded.replaceAll(' ', '');
    final words = folded.split(' ').where((w) => w.isNotEmpty).toList();
    final kept = words.where((w) => !_fillers.contains(w)).toList();
    final use = kept.isEmpty ? words : kept;
    stems = use.map(stemWord).toList();
    joined = stemWord(use.join());
  }

  late final String flat;
  late final List<String> stems;
  late final String joined;
}

/// Whether [part] occurs as contiguous run of whole words in [whole].
bool _wordRun(List<String> part, List<String> whole) {
  if (part.isEmpty || part.length >= whole.length) return false;
  if (part.join().length < 3) return false;
  for (var i = 0; i + part.length <= whole.length; i++) {
    var ok = true;
    for (var k = 0; k < part.length && ok; k++) {
      ok = whole[i + k] == part[k];
    }
    if (ok) return true;
  }
  return false;
}

/// Stem of a whole name: filler words dropped, words stemmed and joined
/// without spaces („Smart SSH“ = „SmartSSH“).
String stemName(String s) => _Key(s).stems.join();

/// Match tier of [query] against [candidate]:
/// 3 = equal ignoring case, umlauts, punctuation and spaces;
/// 2 = same word stems (plural/singular, „Einkaufsliste“ ≈ „Einkaufen“);
/// 1 = all words of one occur as whole words in the other („Urlaub“ ≈
/// „Urlaub Ideen“; never inside a compound like „Hausarbeit“);
/// 0 = no match.
int matchScore(String query, String candidate) {
  final a = _Key(query);
  final b = _Key(candidate);
  if (a.flat.isEmpty || b.flat.isEmpty) return 0;
  if (a.flat == b.flat) return 3;
  if (a.stems.join() == b.stems.join() || a.joined == b.joined) return 2;
  if (_wordRun(a.stems, b.stems) || _wordRun(b.stems, a.stems)) return 1;
  return 0;
}

/// Result of [bestMatches]: the candidates with the highest score.
typedef Matches<T> = ({int score, List<T> best});

/// The candidates of [items] that match [query] best, using every name
/// [namesOf] returns per candidate.
Matches<T> bestMatches<T>(
  String query,
  Iterable<T> items,
  Iterable<String> Function(T) namesOf,
) {
  var top = 0;
  var best = <T>[];
  for (final item in items) {
    var score = 0;
    for (final n in namesOf(item)) {
      final s = matchScore(query, n);
      if (s > score) score = s;
    }
    if (score == 0) continue;
    if (score > top) {
      top = score;
      best = [item];
    } else if (score == top) {
      best.add(item);
    }
  }
  return (score: top, best: best);
}
