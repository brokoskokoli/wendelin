/// Texts of the agent run for protected data.
library;

import 'package:wendelin_core/wendelin_core.dart';

/// Model- and user-facing texts of the `AgentRunner` for protected data.
abstract final class AgentRunnerTexts {
  /// Replaces assistant text that was built from results the target may not
  /// see.
  static const placeholder = '[Inhalt aus geschützter Quelle ausgeblendet]';

  /// Appended to the system prompt when the profile offers no tools.
  static const noToolsNote =
      'Über dieses Profil sind keine Aktionen möglich (keine Tools). '
      'Behaupte nie, etwas ausgeführt oder erledigt zu haben.';

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

  /// Result text of a tool call that was undone because the answer asking
  /// for it ended with a red receipt.
  static const undoneUnverified =
      'Rückgängig gemacht: Die Antwort des Modells konnte nicht verifiziert '
      'werden (TEE-Prüfung), die Aktion wurde zurückgenommen.';

  /// Result text when that undo failed (the user must check).
  static const undoFailedUnverified =
      'Die Antwort des Modells konnte nicht verifiziert werden (TEE-Prüfung); '
      'die Aktion ließ sich nicht automatisch rückgängig machen. Bitte '
      'prüfen.';

  /// Short notice (written and spoken) when an undo failed.
  static const undoFailedNotice =
      'Hinweis: Eine Aktion ließ sich nicht zurücknehmen, bitte prüfen.';

  /// Message when a private request has no target with enough privacy.
  static const noPrivateTarget =
      'Die Anfrage ist privat, aber kein ausreichend geschütztes Modell ist '
      'verfügbar. Ich habe sie deshalb nicht gesendet.';

  /// Message when the chosen provider fails (after one retry): the reason
  /// in a short sentence that is also fine to speak, in [language] (`de`,
  /// `fr`, `en`; else German). It never contains the raw exception text.
  /// Wendelin does not switch to another provider on its own (K28).
  static String providerFailure(
    String name,
    ProviderException error, {
    String? language,
  }) {
    final t = _lang(language);
    return switch (error) {
      NetworkException() => t(
        '$name ist gerade nicht erreichbar.',
        '$name est actuellement injoignable.',
        '$name is not reachable right now.',
      ),
      ProviderTimeoutException() => t(
        '$name antwortet nicht rechtzeitig.',
        '$name ne répond pas à temps.',
        '$name does not answer in time.',
      ),
      RateLimitException() => t(
        '$name hat das Kontingent erreicht (zu viele Anfragen).',
        '$name a atteint son quota (trop de requêtes).',
        '$name has reached its quota (too many requests).',
      ),
      ServerException() => t(
        '$name ist gerade überlastet oder gestört.',
        '$name est surchargé ou en panne.',
        '$name is overloaded or down right now.',
      ),
      AuthException() => t(
        '$name hat den Zugang abgelehnt. Bitte den API-Schlüssel prüfen.',
        '$name a refusé l’accès. Vérifie la clé API.',
        '$name rejected the access. Please check the API key.',
      ),
      InvalidRequestException() => t(
        '$name kennt das Modell oder die Anfrage nicht.',
        '$name ne connaît pas le modèle ou la requête.',
        '$name does not know the model or the request.',
      ),
      MalformedResponseException() => t(
        '$name hat eine unverständliche Antwort geschickt.',
        '$name a envoyé une réponse incompréhensible.',
        '$name sent an answer that could not be understood.',
      ),
      AttestationFailedException() => t(
        'Die Prüfung von $name ist fehlgeschlagen.',
        'La vérification de $name a échoué.',
        'The verification of $name failed.',
      ),
      CancelledException() => t('Abgebrochen.', 'Annulé.', 'Cancelled.'),
    };
  }

  /// Message when the user named a target („nochmal mit X“, prefix „X, …“)
  /// that cannot be used: [reason] is `missing`, `disabled` or `incomplete`.
  /// Nothing else answers instead (K28).
  static String targetUnavailable(
    String name,
    String reason, {
    String? language,
  }) {
    final t = _lang(language);
    final why = switch (reason) {
      'disabled' => t('ist abgeschaltet', 'est désactivé', 'is switched off'),
      'missing' => t(
        'existiert nicht mehr',
        'n’existe plus',
        'no longer exists',
      ),
      _ => t(
        'ist nicht fertig eingerichtet',
        'n’est pas entièrement configuré',
        'is not fully set up',
      ),
    };
    return t(
      '$name ist nicht verfügbar: Es $why. Ich habe die Anfrage nicht '
          'gesendet.',
      '$name n’est pas disponible : il $why. Je n’ai pas envoyé la requête.',
      '$name is not available: it $why. I did not send the request.',
    );
  }

  /// Message when the user declined „nochmal mit X“ below the privacy
  /// floor: nothing is sent, the first target does not answer instead.
  static String notSent(String name, {String? language}) => _lang(language)(
    'Nicht gesendet: Du hast $name für diese private Anfrage abgelehnt.',
    'Non envoyé : tu as refusé $name pour cette requête privée.',
    'Not sent: you declined $name for this private request.',
  );

  static String Function(String de, String fr, String en) _lang(
    String? language,
  ) {
    final code = language?.split(RegExp('[-_]')).first.toLowerCase();
    return (de, fr, en) => switch (code) {
      'fr' => fr,
      'en' => en,
      _ => de,
    };
  }

  /// Error text for a call to a tool the current target may not see.
  static String hiddenTool(String name) =>
      'Das Tool „$name“ steht diesem Modell nicht zur Verfügung. Nutze nur '
      'Tools aus der Tool-Liste.';
}
