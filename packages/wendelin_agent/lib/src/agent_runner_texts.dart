/// Texts of the agent run for protected data.
library;

/// Model- and user-facing texts of the `AgentRunner` for protected data.
abstract final class AgentRunnerTexts {
  /// Replaces assistant text that was built from results the target may not
  /// see.
  static const placeholder = '[Inhalt aus geschützter Quelle ausgeblendet]';

  /// Replaces results of tools the target may not see and every result in
  /// a protected section.
  static const redactedResult =
      '[Tool-Ergebnis aus geschützter Quelle ausgeblendet]';

  /// Replaces messages of an earlier private turn for targets below its
  /// privacy floor.
  static const privateHidden = '[privater Gesprächsteil ausgeblendet]';

  /// Message when a private request has no target with enough privacy.
  static const noPrivateTarget =
      'Die Anfrage ist privat, aber kein ausreichend geschütztes Modell ist '
      'verfügbar. Ich habe sie deshalb nicht gesendet.';

  /// Message when the user declines handing protected data to another
  /// model.
  static const protectedDeclined =
      'Die Anfrage enthält Daten aus geschützten Quellen. Ohne deine '
      'Zustimmung gebe ich sie nicht an ein anderes Modell weiter, deshalb '
      'habe ich hier aufgehört.';

  /// Error text for a call to a tool the current target may not see.
  static String hiddenTool(String name) =>
      'Das Tool „$name“ steht diesem Modell nicht zur Verfügung. Nutze nur '
      'Tools aus der Tool-Liste.';
}
