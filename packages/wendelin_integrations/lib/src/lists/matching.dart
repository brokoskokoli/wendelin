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
      'é' || 'è' || 'ê' => 'e',
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

/// Stem of a whole name: filler words dropped, `ae/oe/ue` read as
/// umlauts, words stemmed and joined without spaces („Smart SSH“ =
/// „SmartSSH“).
String stemName(String s) {
  final words = normalizeText(s)
      .replaceAll('ae', 'a')
      .replaceAll('oe', 'o')
      .replaceAll('ue', 'u')
      .split(' ')
      .where((w) => w.isNotEmpty);
  final kept = words.where((w) => !_fillers.contains(w)).toList();
  return (kept.isEmpty ? words : kept).map(stemWord).join();
}

/// How well [query] matches [candidate]: 3 = equal ignoring case,
/// umlauts and punctuation; 2 = same stem; 1 = one stem contains the
/// other (at least 3 characters); 0 = no match.
int matchScore(String query, String candidate) {
  final q = normalizeText(query).replaceAll(' ', '');
  final c = normalizeText(candidate).replaceAll(' ', '');
  if (q.isEmpty || c.isEmpty) return 0;
  if (q == c) return 3;
  final qs = stemName(query);
  final cs = stemName(candidate);
  if (qs.isEmpty || cs.isEmpty) return 0;
  if (qs == cs) return 2;
  if (qs.length >= 3 &&
      cs.length >= 3 &&
      (qs.contains(cs) || cs.contains(qs))) {
    return 1;
  }
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
