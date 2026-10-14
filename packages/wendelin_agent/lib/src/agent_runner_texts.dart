/// Texts of the agent run for protected data.
library;

import 'package:wendelin_core/wendelin_core.dart';

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

  /// Error text for an `external` tool call whose answer could not be
  /// verified (TEE receipt red or missing).
  static const unverifiedAnswer =
      'Nicht ausgeführt: Die Antwort des Modells konnte nicht verifiziert '
      'werden (TEE-Prüfung).';

  /// Message when a private request has no target with enough privacy.
  static const noPrivateTarget =
      'Die Anfrage ist privat, aber kein ausreichend geschütztes Modell ist '
      'verfügbar. Ich habe sie deshalb nicht gesendet.';

  /// Message when the chosen provider fails (after one retry): the reason
  /// in a short sentence that is also fine to speak. Wendelin does not
  /// switch to another provider on its own (K28).
  static String providerFailure(String name, ProviderException error) =>
      switch (error) {
        NetworkException() => '$name ist gerade nicht erreichbar.',
        ProviderTimeoutException() => '$name antwortet nicht rechtzeitig.',
        RateLimitException() =>
          '$name hat das Kontingent erreicht (zu viele Anfragen).',
        ServerException() => '$name ist gerade überlastet oder gestört.',
        AuthException() =>
          '$name hat den Zugang abgelehnt. Bitte den API-Schlüssel prüfen.',
        InvalidRequestException() =>
          '$name kennt das Modell oder die Anfrage nicht: ${error.message}',
        MalformedResponseException() =>
          '$name hat eine unverständliche Antwort geschickt.',
        AttestationFailedException() =>
          'Die Prüfung von $name ist fehlgeschlagen: ${error.message}',
        CancelledException() => 'Abgebrochen.',
      };

  /// Error text for a call to a tool the current target may not see.
  static String hiddenTool(String name) =>
      'Das Tool „$name“ steht diesem Modell nicht zur Verfügung. Nutze nur '
      'Tools aus der Tool-Liste.';
}
