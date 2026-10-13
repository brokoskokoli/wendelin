/// Local clean-up of one spoken sentence (WP41, stage 0): the safety net
/// when the model did not write speech-friendly text. Restrained and
/// language dependent (de/fr/en, anything else is German).
library;

final _time = RegExp(
  r'(?<![\d:.,])([01]?\d|2[0-3]):([0-5]\d)(?![\d:])'
  r'(?:\s*(?:Uhr|uhr|h|heures|a\.m\.|p\.m\.))?',
);
final _arrows = RegExp('[\u2190-\u21FF\u27F5-\u27FF\u2B05-\u2B07]|->|=>|<-');
final _colonEnd = RegExp(r'\s*:+(?=[\s)»”"]*$)');
final _colonLower = RegExp(r'(?<=\p{L})\s?:\s+(?=\p{Ll})', unicode: true);
final _colonOther = RegExp(
  r'(?<=\p{L})\s?:\s+(?=[\p{Lu}\p{N}„“"«(])',
  unicode: true,
);
final _doubleDot = RegExp(r'([ap]\.m\.)\.');
final _spaces = RegExp(r'\s+');

/// Abbreviations: pattern → spoken form, per language. The dot of an
/// abbreviation at the end of the sentence stays as sentence end.
const _abbreviations = <String, List<(String, String)>>{
  'de': [
    (r'z\.\s?B\.', 'zum Beispiel'),
    (r'd\.\s?h\.', 'das heißt'),
    (r'u\.\s?a\.', 'unter anderem'),
    (r'u\.\s?U\.', 'unter Umständen'),
    (r'ca\.', 'circa'),
    (r'usw\.', 'und so weiter'),
    (r'bzw\.', 'beziehungsweise'),
    (r'evtl\.', 'eventuell'),
    (r'ggf\.', 'gegebenenfalls'),
    (r'inkl\.', 'inklusive'),
    (r'vgl\.', 'vergleiche'),
    (r'etc\.', 'et cetera'),
  ],
  'fr': [
    (r'p\.\s?ex\.', 'par exemple'),
    (r'c\.-à-d\.', 'c’est-à-dire'),
    (r'env\.', 'environ'),
    (r'etc\.', 'et cetera'),
  ],
  'en': [
    (r'e\.g\.', 'for example'),
    (r'i\.e\.', 'that is'),
    (r'approx\.', 'approximately'),
    (r'etc\.', 'et cetera'),
    (r'vs\.', 'versus'),
  ],
};

final _compiled = {
  for (final e in _abbreviations.entries)
    e.key: [
      for (final (pattern, spoken) in e.value)
        (
          RegExp('(?<![\\p{L}\\p{N}])$pattern(?=\\s|\$)', unicode: true),
          spoken,
        ),
    ],
};

String _lang(String? language) {
  final code = language?.split(RegExp('[-_]')).first.toLowerCase();
  return code == 'fr' || code == 'en' ? code! : 'de';
}

/// Rewrites [sentence] for the speech output in [language]:
/// times (`10:30` → „10 Uhr 30“), abbreviations, arrows, and colons
/// (at the end or before a capital → period, before a lower-case word →
/// comma).
String normalizeForSpeech(String sentence, String? language) {
  final lang = _lang(language);
  var s = sentence.replaceAllMapped(_time, (m) {
    final h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    return switch (lang) {
      'fr' => '$h ${h == 1 ? 'heure' : 'heures'}${min == 0 ? '' : ' $min'}',
      'en' => _english(h, min),
      _ => '$h Uhr${min == 0 ? '' : ' $min'}',
    };
  });
  for (final (re, spoken) in _compiled[lang]!) {
    s = s.replaceAllMapped(re, (m) => m.end == s.length ? '$spoken.' : spoken);
  }
  s = s
      .replaceAll(_arrows, ' ')
      .replaceAll(_colonEnd, '.')
      .replaceAll(_colonLower, ', ')
      .replaceAll(_colonOther, '. ')
      .replaceAll(_spaces, ' ')
      .replaceAllMapped(_doubleDot, (m) => m[1]!)
      .trim();
  return s;
}

String _english(int h, int min) {
  final suffix = h < 12 ? 'a.m.' : 'p.m.';
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final minutes = min == 0 ? '' : ':${min.toString().padLeft(2, '0')}';
  return '$h12$minutes $suffix';
}
