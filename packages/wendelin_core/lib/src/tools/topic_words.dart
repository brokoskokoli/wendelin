import '../text/fold.dart';
import 'topic_words/de.dart';
import 'topic_words/en.dart';
import 'topic_words/fr.dart';

/// Topic words per language (key = language code), each map keyed by
/// integration id. One list for the routing condition `needsTool`
/// (`KeywordToolCategoryMatcher`), the tool search and the preloading of
/// tools before the first model call (WP119). New languages: see
/// `topic_words/README.md`.
const topicWordsByLanguage = <String, Map<String, List<String>>>{
  'de': topicWordsDe,
  'en': topicWordsEn,
  'fr': topicWordsFr,
};

/// Language used when a tag is unknown or empty.
const fallbackTopicLanguage = 'en';

/// The topic words for a BCP 47 tag such as `de-DE` or `fr`; an unknown
/// language gets [fallbackTopicLanguage].
Map<String, List<String>> topicWordsFor(String? languageTag) {
  final code = (languageTag ?? '').toLowerCase().split(RegExp('[-_]')).first;
  return topicWordsByLanguage[code] ??
      topicWordsByLanguage[fallbackTopicLanguage]!;
}

/// Integration ids whose topic words (in [languageTag]'s language) occur in
/// [text], in the order of the word list. Words are stems on word
/// boundaries; case and diacritics do not matter ([foldForMatch]).
List<String> topicIntegrationsIn(String text, {String? languageTag}) =>
    topicIntegrationsWith(text, topicWordsFor(languageTag));

/// Like [topicIntegrationsIn] with explicit [topics].
List<String> topicIntegrationsWith(
  String text,
  Map<String, List<String>> topics,
) {
  final folded = foldForMatch(text);
  if (folded.isEmpty) return const [];
  final words = folded.split(' ');
  return [
    for (final MapEntry(:key, :value) in topics.entries)
      if (value.any((phrase) => _hasStems(words, foldForMatch(phrase)))) key,
  ];
}

bool _hasStems(List<String> words, String phrase) {
  if (phrase.isEmpty) return false;
  final stems = phrase.split(' ');
  for (var i = 0; i + stems.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < stems.length && ok; j++) {
      ok = words[i + j].startsWith(stems[j]);
    }
    if (ok) return true;
  }
  return false;
}
