/// Recognises answers in which the model says it cannot solve the task
/// (concept: „Antwortklassifikation per Schlüsselwörtern“), in German,
/// French and English.
///
/// The phrases are deliberately first-person and about *helping/doing*, so
/// that ordinary negative results („Ich kann keinen Termin finden“, „I can't
/// find any events“) do not trigger an escalation.
final class GiveUpClassifier {
  /// Creates a classifier; [phrases] replaces the default list.
  GiveUpClassifier({List<String>? phrases})
    : phrases = List.unmodifiable((phrases ?? defaultPhrases).map(_normalize));

  /// Default phrases (lower case).
  static const defaultPhrases = [
    // de
    'das kann ich nicht',
    'kann ich leider nicht',
    'kann ich nicht helfen',
    'kann ich dir nicht helfen',
    'kann ich ihnen nicht helfen',
    'kann ich nicht erledigen',
    'kann ich nicht beantworten',
    'ich bin nicht in der lage',
    'bin ich nicht in der lage',
    'ich habe keinen zugriff',
    'habe ich keinen zugriff',
    'übersteigt meine fähigkeiten',
    // fr
    'je ne peux pas vous aider',
    "je ne peux pas t'aider",
    'je ne peux pas faire',
    'je ne suis pas en mesure',
    'je suis incapable',
    "je n'ai pas accès",
    'dépasse mes capacités',
    // en
    "i can't help",
    'i cannot help',
    "i can't do that",
    'i cannot do that',
    "i'm unable to help",
    'i am unable to help',
    "i'm not able to",
    'i am not able to',
    "i don't have access",
    'i do not have access',
    'beyond my capabilities',
  ];

  /// Normalised phrases.
  final List<String> phrases;

  /// Whether [answer] says that the model gives up.
  bool isGiveUp(String answer) {
    final text = _normalize(answer);
    return phrases.any(text.contains);
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[’‘`´]'), "'")
      .replaceAll(RegExp(r'\s+'), ' ');
}
