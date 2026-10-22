import '../text/fold.dart';
import 'ha_words/de.dart';
import 'ha_words/en.dart';
import 'ha_words/fr.dart';

/// What a user can ask a smart-home device to do (word lists per language:
/// [HaWords.actions]). `half` stands for „50 %“ in words; percent values
/// are the digits next to a [HaWords.percent] word.
enum HaAction {
  /// Switch on.
  on,

  /// Switch off.
  off,

  /// Open (raise a blind).
  open,

  /// Close (lower a blind).
  close,

  /// Stop a moving cover.
  stop,

  /// Brighter.
  brighter,

  /// Dimmer.
  dimmer,

  /// „halb“ = 50 %.
  half,
}

/// Device type and action words of one language (WP135). Kept apart per
/// language like the topic words (WP119); one test checks that every
/// language covers every device type and every action. Used by the device
/// lookup (type + room), the preloading and the fast path.
///
/// Matching (see [haDomainsIn], [haActionsIn]) works on folded text
/// ([foldForMatch]: case, umlauts and accents do not matter):
/// - [types] and [recognitionErrors] are word **stems** (prefix of a word);
/// - [actions], [percent] and [degrees] are **whole words** or phrases
///   (short words like „an“ or „zu“ must not match inside other words).
final class HaWords {
  /// Creates a word list.
  const HaWords({
    required this.types,
    required this.recognitionErrors,
    required this.actions,
    required this.percent,
    required this.degrees,
    required this.fillers,
    required this.neutral,
  });

  /// Device type words per Home Assistant domain (`light`, `cover`,
  /// `switch`, `climate`): stems.
  final Map<String, List<String>> types;

  /// Typical slips of the speech recognition per domain (de „Rolle“ for
  /// „Rollo“), stems; used like [types] to find a device, not for the
  /// preloading on their own.
  final Map<String, List<String>> recognitionErrors;

  /// Action words and phrases per [HaAction], colloquial variants included.
  final Map<HaAction, List<String>> actions;

  /// Words after a number meaning percent.
  final List<String> percent;

  /// Words after a number meaning degrees (thermostat).
  final List<String> degrees;

  /// Articles and prepositions that carry no meaning for finding a device
  /// („die Lampe im Wohnzimmer“), whole words.
  final List<String> fillers;

  /// Verbs of the request, politeness and the wake word („mach“, „bitte“,
  /// „hey“, „wendelin“), whole words. Known to the fast path, but they carry
  /// no meaning: the fast path accepts an utterance only if **every** word
  /// is known (like `matchLockedCommand`).
  final List<String> neutral;
}

/// Word lists per language code. New language: see `ha_words/README.md`.
const haWordsByLanguage = <String, HaWords>{
  'de': haWordsDe,
  'en': haWordsEn,
  'fr': haWordsFr,
};

/// Extra topic words of the `ha` integration per language (WP135), added to
/// `topicWordsByLanguage`. Together with the device type stems.
const haTopicExtraByLanguage = <String, List<String>>{
  'de': haTopicWordsDe,
  'en': haTopicWordsEn,
  'fr': haTopicWordsFr,
};

/// The word list for a BCP 47 tag such as `de-DE`; unknown → English (like
/// the topic words).
HaWords haWordsFor(String? languageTag) {
  final code = (languageTag ?? '').toLowerCase().split(RegExp('[-_]')).first;
  return haWordsByLanguage[code] ?? haWordsByLanguage['en']!;
}

/// Home Assistant domains whose type words (or recognition slips) occur in
/// [text]. [languageTag] `null` = every language (names in the device list
/// may be in any language).
Set<String> haDomainsIn(String text, {String? languageTag}) {
  final words = foldForMatch(text).split(' ');
  if (words.isEmpty || words.first.isEmpty) return const {};
  final lists = languageTag == null
      ? haWordsByLanguage.values
      : [haWordsFor(languageTag)];
  return {
    for (final w in lists)
      for (final MapEntry(:key, :value) in w.types.entries)
        if ([
          ...value,
          ...?w.recognitionErrors[key],
        ].any((stem) => _hasStems(words, foldForMatch(stem))))
          key,
  };
}

/// The words of [text] that are neither type words nor fillers (the room or
/// name part), folded, space separated.
String haWithoutTypeWords(String text, {String? languageTag}) {
  final lists = languageTag == null
      ? haWordsByLanguage.values
      : [haWordsFor(languageTag)];
  final fillers = {for (final w in lists) ...w.fillers.map(foldForMatch)};
  final stems = [
    for (final w in lists)
      for (final e in w.types.entries) ...[
        ...e.value,
        ...?w.recognitionErrors[e.key],
      ],
  ].map(foldForMatch).where((s) => s.isNotEmpty && !s.contains(' ')).toList();
  return foldForMatch(text)
      .split(' ')
      .where((word) => !fillers.contains(word) && !stems.any(word.startsWith))
      .join(' ');
}

/// The actions whose words occur in [text] (whole words, phrases in
/// order). More than one action in a text is a signal for „unclear“.
Set<HaAction> haActionsIn(String text, {String? languageTag}) {
  final words = foldForMatch(text).split(' ');
  if (words.isEmpty || words.first.isEmpty) return const {};
  final w = haWordsFor(languageTag);
  return {
    for (final MapEntry(:key, :value) in w.actions.entries)
      if (value.any((phrase) => _hasWords(words, foldForMatch(phrase)))) key,
  };
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

bool _hasWords(List<String> words, String phrase) {
  if (phrase.isEmpty) return false;
  final parts = phrase.split(' ');
  for (var i = 0; i + parts.length <= words.length; i++) {
    var ok = true;
    for (var j = 0; j < parts.length && ok; j++) {
      ok = words[i + j] == parts[j];
    }
    if (ok) return true;
  }
  return false;
}
