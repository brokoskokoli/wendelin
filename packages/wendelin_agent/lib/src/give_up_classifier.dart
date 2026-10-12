/// Recognises answers in which the model says it cannot solve the task
/// (concept: „Antwortklassifikation per Schlüsselwörtern“), in German,
/// French and English.
///
/// The patterns are first-person and bound to *helping/doing* or to the end
/// of the sentence, so that ordinary negative results („Den Termin kann ich
/// leider nicht verschieben, er ist schon vorbei“, „Das kann ich nicht
/// finden“, „I'm not able to find any events“) do not trigger an escalation.
final class GiveUpClassifier {
  /// Creates a classifier; [patterns] (matched against the lower-cased
  /// answer with normalised apostrophes and spaces) replaces
  /// [defaultPatterns].
  GiveUpClassifier({List<RegExp>? patterns})
    : patterns = List.unmodifiable(patterns ?? defaultPatterns);

  static const _end = r'\s*(?:[.!…]|$)';
  static const _doDe =
      r'(?:helfen|tun|machen|erledigen|beantworten|übernehmen)';
  static const _doEn = r'(?:help|assist|do (?:that|this|it))';

  /// Default patterns.
  static final defaultPatterns = <RegExp>[
    // de: „Dabei kann ich dir leider nicht helfen.“, „Das kann ich nicht.“
    RegExp(
      r'kann ich (?:dir |ihnen |euch )?(?:dabei |damit |hierbei )?'
      r'(?:leider )?(?:nicht|nichts) '
      '$_doDe',
    ),
    RegExp(
      r'\b(?:das|dabei|damit|hierbei|dies) kann ich '
      r'(?:dir |ihnen )?(?:leider )?(?:nicht|nichts)'
      '$_end',
    ),
    RegExp(
      r'(?:ich bin|bin ich) (?:leider )?nicht in der lage'
      r'(?:'
      '$_end'
      r'|, (?:das|dies|dir|ihnen|dabei) )',
    ),
    // Only a bare „keinen Zugriff“ at the end of the sentence: „Ich habe
    // keinen Zugriff auf deinen Kalender, bitte erlaube ihn …“ is a useful
    // answer, not a reason to escalate.
    RegExp(
      r'(?:ich habe|habe ich) (?:leider )?keinen zugriff'
      r'(?: darauf| auf das internet)?'
      '$_end',
    ),
    RegExp(r'übersteigt meine fähigkeiten'),
    // fr
    RegExp(
      r'je ne (?:peux|suis) pas (?:en mesure de )?'
      r"(?:vous |t'|te )?(?:aider|faire (?:ça|cela))",
    ),
    RegExp(
      r'je ne peux pas'
      '$_end',
    ),
    RegExp(r'je suis (?:malheureusement )?incapable'),
    RegExp(
      r"je n'ai pas accès(?: à (?:cela|internet))?"
      '$_end',
    ),
    RegExp(r'dépasse mes capacités'),
    // en
    RegExp(
      r"i (?:can't|cannot|can not|am unable to|'m unable to|"
      r"am not able to|'m not able to) "
      '$_doEn',
    ),
    RegExp(
      r"i (?:can't|cannot)"
      '$_end',
    ),
    RegExp(
      r"i (?:don't|do not) have access(?: to (?:that|this|the internet))?"
      '$_end',
    ),
    RegExp(r'beyond my capabilities'),
  ];

  /// Patterns in use.
  final List<RegExp> patterns;

  /// Whether [answer] says that the model gives up.
  bool isGiveUp(String answer) {
    final text = answer
        .toLowerCase()
        .replaceAll(RegExp('[’‘`´]'), "'")
        .replaceAll(RegExp(r'\s+'), ' ');
    return patterns.any((p) => p.hasMatch(text));
  }
}
