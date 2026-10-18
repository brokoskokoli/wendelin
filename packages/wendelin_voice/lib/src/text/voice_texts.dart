import 'package:wendelin_core/wendelin_core.dart';

/// Spoken phrases of the voice pipeline in German, French and English.
///
/// Languages are matched by their primary subtag (`de-AT` → `de`); unknown
/// languages fall back to German.
final class VoiceTexts {
  const VoiceTexts._(
    this.language, {
    required this.rest,
    required this.nothingUnderstood,
    required this.and,
    required this.more,
    required this.tooSlow,
    required this.noBudget,
    required this.failed,
    required this.unverified,
  });

  /// German.
  static const de = VoiceTexts._(
    'de',
    rest: 'Den Rest siehst du auf dem Bildschirm.',
    nothingUnderstood: 'Ich habe nichts verstanden.',
    and: 'und',
    more: _moreDe,
    tooSlow: 'Das hat zu lange gedauert.',
    noBudget: 'Das Budget ist aufgebraucht.',
    failed: 'Das hat leider nicht geklappt.',
    unverified: 'Achtung, diese Antwort konnte nicht verifiziert werden.',
  );

  /// French.
  static const fr = VoiceTexts._(
    'fr',
    rest: 'La suite est à l’écran.',
    nothingUnderstood: 'Je n’ai rien compris.',
    and: 'et',
    more: _moreFr,
    tooSlow: 'Cela a pris trop de temps.',
    noBudget: 'Le budget est épuisé.',
    failed: 'Je n’ai pas pu répondre.',
    unverified: 'Attention, cette réponse n’a pas pu être vérifiée.',
  );

  /// English.
  static const en = VoiceTexts._(
    'en',
    rest: 'The rest is on the screen.',
    nothingUnderstood: 'I did not catch that.',
    and: 'and',
    more: _moreEn,
    tooSlow: 'That took too long.',
    noBudget: 'The budget is used up.',
    failed: 'Sorry, that did not work.',
    unverified: 'Careful, this answer could not be verified.',
  );

  /// Texts for [language] (BCP 47; `null` = German).
  static VoiceTexts of(String? language) =>
      switch (language?.split(RegExp('[-_]')).first.toLowerCase()) {
        'fr' => fr,
        'en' => en,
        _ => de,
      };

  /// Primary language subtag.
  final String language;

  /// Hint that more content is only on the screen.
  final String rest;

  /// Said when no usable speech was recognized.
  final String nothingUnderstood;

  /// Conjunction for the last list item.
  final String and;

  /// „und 4 weitere“ for the number of omitted list items.
  final String Function(int count) more;

  /// Said when the agent ran out of time.
  final String tooSlow;

  /// Said when a budget blocks the request.
  final String noBudget;

  /// Said for other failures.
  final String failed;

  /// Said after the speech was stopped because the receipt of the answer
  /// turned out red (WP81).
  final String unverified;

  /// Spoken text for a failed agent run. In German the agent's own (German,
  /// more specific) [message] is used. A provider failure carries the
  /// reason already translated into the request language (`AgentRunnerTexts`,
  /// never the raw exception text), so it is spoken in every language; other
  /// languages get a short generic phrase for [kind], so the answer language
  /// does not switch.
  String failure(AgentErrorKind kind, String message) {
    final usable = message.trim().isNotEmpty;
    if (usable && (language == 'de' || kind == AgentErrorKind.provider)) {
      return message;
    }
    return switch (kind) {
      AgentErrorKind.timeout => tooSlow,
      AgentErrorKind.tokenBudget || AgentErrorKind.budgetBlocked => noBudget,
      _ => failed,
    };
  }

  static String _moreDe(int n) => 'und $n weitere';
  static String _moreFr(int n) => n == 1 ? 'et 1 autre' : 'et $n autres';
  static String _moreEn(int n) => 'and $n more';
}
