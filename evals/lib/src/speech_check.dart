/// Checks whether an answer text can be read aloud as it is (WP41 eval):
/// no Markdown or lists, no colons or clock notation, no abbreviations,
/// emojis, arrows or URLs, and short.
library;

final _markdown = RegExp(
  r'[*#`|]|__|^\s*(?:[-+]|\d{1,2}[.)])\s',
  multiLine: true,
);
final _colon = RegExp(':');
final _abbreviation = RegExp(
  r'\b(?:z\.\s?B\.|d\.\s?h\.|u\.\s?a\.|ca\.|usw\.|bzw\.|evtl\.|ggf\.|inkl\.|'
  r'p\.\s?ex\.|env\.|e\.g\.|i\.e\.|approx\.|vs\.|etc\.)',
  caseSensitive: false,
);
final _symbols = RegExp('[\u{1F000}-\u{1FAFF}←-⇿☀-➿⬀-⯿]|->|=>', unicode: true);
final _url = RegExp(r'https?://|www\.');
final _tag = RegExp('</?spoken>');
final _sentenceEnd = RegExp(r'[.!?…]+(?=\s|$)');

/// What is wrong with [text] for speech output (empty = clean).
///
/// - `markdown`: emphasis, headings, tables, code, list markers
/// - `doppelpunkt`: a colon (also in `10:30`)
/// - `abkürzung`: z. B., ca., usw., e.g., …
/// - `symbol`: emoji, arrows
/// - `url`
/// - `tag`: a leftover `<spoken>` tag
/// - `lang`: more than [maxSentences] sentences or [maxChars] characters
/// - `zeilen`: several lines (a list or paragraphs)
List<String> speechIssues(
  String text, {
  int maxSentences = 3,
  int maxChars = 400,
}) {
  final t = text.trim();
  final sentences = _sentenceEnd.allMatches(t).length;
  return [
    if (_markdown.hasMatch(t)) 'markdown',
    if (_colon.hasMatch(t)) 'doppelpunkt',
    if (_abbreviation.hasMatch(t)) 'abkürzung',
    if (_symbols.hasMatch(t)) 'symbol',
    if (_url.hasMatch(t)) 'url',
    if (_tag.hasMatch(t)) 'tag',
    if (sentences > maxSentences || t.length > maxChars) 'lang',
    if (t.contains('\n')) 'zeilen',
  ];
}
