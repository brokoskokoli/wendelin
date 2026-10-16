/// What one check stage does and what its outcome means (WP78). Plain
/// words for the „Details“ page; the result of the check itself comes from
/// the log, not from here.
final class StageExplanation {
  /// Creates the explanation.
  const StageExplanation({
    required this.what,
    required this.ifPass,
    required this.ifInfo,
  });

  /// What is checked.
  final String what;

  /// What a pass means for security.
  final String ifPass;

  /// What it means when the stage is only logged (the provider does not
  /// deliver it, or the app does not check it).
  final String ifInfo;
}

const _failMeaning =
    'Die Prüfung ist fehlgeschlagen. Das kann ein Hinweis auf eine '
    'Manipulation oder einen Fehler beim Anbieter sein. Wendelin sendet dann '
    'nichts mehr an diesen Anbieter, bis du ihn neu prüfst.';

const _warnMeaning =
    'Die Prüfung ist bestanden, aber mit einem Hinweis (zum Beispiel ein '
    'ausstehendes Sicherheits-Update des Betreibers). Das schwächt den Schutz '
    'etwas. Es bleibt im Prüfprotokoll sichtbar.';

const _unavailableMeaning =
    'Die Prüfung konnte nicht abgeschlossen werden (zum Beispiel wegen des '
    'Netzes). Sie wird später wiederholt. Bis dahin ist die Stufe '
    'unbestätigt.';

/// Explanation of [stage] (stage id such as `quote`), or `null` if unknown.
StageExplanation? stageExplanationFor(String stage) => _explanations[stage];

/// What a result of [stage] means: [result] is `pass`, `info`, `warn`,
/// `fail` or `unavailable`.
///
/// [tlsResult] is the result of the `tls.spki` stage of the same check: the
/// meaning of an unencrypted request depends on whether the connection is
/// pinned to the attestation.
String stageMeaning(String stage, String result, {String? tlsResult}) {
  final e = _explanations[stage];
  if (stage == 'e2ee.request' && result == 'info') {
    return tlsResult == 'pass'
        ? 'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich '
              'verschlüsselt, nur über die geprüfte Verbindung geschützt.'
        : 'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich '
              'verschlüsselt, und die Verbindung ist nicht an den Nachweis '
              'gebunden. Der Schutz ist dadurch schwächer.';
  }
  return switch (result) {
    'pass' => e?.ifPass ?? 'Die Stufe wurde bestanden.',
    'info' =>
      e?.ifInfo ??
          'Die Stufe wird nur protokolliert, nicht als Bedingung geprüft.',
    'warn' => _warnMeaning,
    'unavailable' => _unavailableMeaning,
    _ => _failMeaning,
  };
}

const _explanations = <String, StageExplanation>{
  'quote': StageExplanation(
    what:
        'Der Hardware-Nachweis (TDX-Quote) der geschützten Umgebung. Er ist '
        'von der CPU signiert und wird gegen die Zertifikate von Intel '
        'geprüft.',
    ifPass:
        'Der Dienst läuft nachweislich in einer echten, abgeschotteten '
        'Intel-TDX-Umgebung. Der Betreiber kann den Speicher nicht mitlesen.',
    ifInfo: 'Der Nachweis wurde nur protokolliert, nicht bewertet.',
  ),
  'tcb': StageExplanation(
    what:
        'Der Sicherheitsstand der Plattform (TCB): ob Firmware und '
        'Mikrocode auf dem aktuellen Stand sind.',
    ifPass: 'Die Plattform hat alle bekannten Sicherheits-Updates.',
    ifInfo: 'Der Sicherheitsstand wurde nur protokolliert.',
  ),
  'nonce': StageExplanation(
    what:
        'Eine zufällige Zahl, die Wendelin mitschickt und die im Nachweis '
        'wieder auftauchen muss.',
    ifPass:
        'Der Nachweis ist frisch für diese Anfrage und kein '
        'aufgezeichneter alter Nachweis.',
    ifInfo: 'Die Zahl wurde nur protokolliert.',
  ),
  'keyset.digest': StageExplanation(
    what:
        'Die Prüfsumme des Schlüsselsatzes (Schlüssel, mit denen Wendelin '
        'verschlüsselt) muss im Hardware-Nachweis stehen.',
    ifPass:
        'Die Schlüssel stammen aus der geprüften Umgebung, nicht von '
        'jemandem dazwischen.',
    ifInfo: 'Die Prüfsumme wurde nur protokolliert.',
  ),
  'keyset.endorsement': StageExplanation(
    what:
        'Eine zusätzliche Signatur über den Schlüsselsatz, die manche '
        'Anbieter liefern.',
    ifPass: 'Der Schlüsselsatz ist zusätzlich vom Anbieter signiert.',
    ifInfo:
        'Dieser Anbieter liefert keine solche Signatur. Die Bindung der '
        'Schlüssel läuft stattdessen über den Hardware-Nachweis (Prüfsumme '
        'des Schlüsselsatzes). Das ist ein etwas schwächerer Beleg, aber '
        'kein Fehler.',
  ),
  'freshness': StageExplanation(
    what: 'Wie alt der Nachweis ist.',
    ifPass: 'Der Nachweis ist aktuell und kein alter Mitschnitt.',
    ifInfo: 'Das Alter wurde nur protokolliert.',
  ),
  'eventlog': StageExplanation(
    what:
        'Das Ereignisprotokoll des Starts: welche Software beim Hochfahren '
        'geladen wurde. Es muss zur Hardware-Messung passen.',
    ifPass: 'Die gestartete Software ist lückenlos nachvollziehbar.',
    ifInfo: 'Das Ereignisprotokoll wurde nur protokolliert.',
  ),
  'compose': StageExplanation(
    what:
        'Der Compose-Hash: eine Prüfsumme der Container-Beschreibung, also '
        'welche Programme im Dienst laufen.',
    ifPass: 'Genau die erwarteten Programme laufen im Dienst.',
    ifInfo:
        'Der Hash wurde protokolliert, aber nicht gegen eine Liste '
        'vertrauenswürdiger Werte verglichen.',
  ),
  'provenance': StageExplanation(
    what:
        'Die Herkunft: aus welchem Quellcode-Stand (Commit) die laufende '
        'Software gebaut wurde und ob er auf der Vertrauensliste steht.',
    ifPass: 'Die Software stammt aus einem bekannten, geprüften Stand.',
    ifInfo:
        'Es gibt keine Vertrauensliste für diesen Anbieter. Wendelin '
        'protokolliert den Stand, kann aber nicht sagen, ob er '
        'vertrauenswürdig ist. Wer den Quellcode prüfen will, kann den '
        'Commit im Prüfprotokoll nachsehen.',
  ),
  'tls.spki': StageExplanation(
    what:
        'Ob die Netzwerkverbindung genau zu dem Schlüssel führt, der im '
        'Hardware-Nachweis steht (Pinning).',
    ifPass:
        'Die Verbindung endet in der geprüften Umgebung, niemand kann sich '
        'dazwischenschalten.',
    ifInfo:
        'Das Zertifikat der Verbindung wurde nicht mit dem Nachweis '
        'verglichen. Dann hängt der Schutz allein an der Ende-zu-Ende-'
        'Verschlüsselung.',
  ),
  'e2ee.key': StageExplanation(
    what:
        'Der Schlüssel, mit dem Wendelin deine Anfrage Ende-zu-Ende '
        'verschlüsselt, stammt aus dem Hardware-Nachweis.',
    ifPass:
        'Nur die geprüfte Umgebung kann die Anfrage entschlüsseln. Bei '
        'manchen Anbietern endet die Verschlüsselung im Gateway, nicht im '
        'Modell selbst.',
    ifInfo: 'Der Schlüssel wurde nur protokolliert.',
  ),
  'e2ee.request': StageExplanation(
    what: 'Ob die Anfrage tatsächlich verschlüsselt gesendet wurde.',
    ifPass: 'Deine Anfrage ist unterwegs für Dritte unlesbar.',
    ifInfo:
        'Die Anfrage (oder Teile wie Tool-Aufrufe) sind nicht zusätzlich '
        'verschlüsselt, nur über die geprüfte Verbindung geschützt.',
  ),
  'e2ee.response': StageExplanation(
    what: 'Ob die Antwort verschlüsselt ankam und entschlüsselt werden konnte.',
    ifPass: 'Die Antwort kam unverändert aus der geprüften Umgebung.',
    ifInfo: 'Die Entschlüsselung wurde nur protokolliert.',
  ),
  'e2ee.keyset': StageExplanation(
    what: 'Ob der Schlüsselsatz der Antwort zum geprüften Satz passt.',
    ifPass: 'Die Antwort gehört zur geprüften Sitzung.',
    ifInfo: 'Der Schlüsselsatz wurde nur protokolliert.',
  ),
  'gateway': StageExplanation(
    what:
        'Der Zustand des Gateways des Anbieters (Vermittler vor dem '
        'Modell).',
    ifPass: 'Das Gateway läuft mit aktuellem Sicherheitsstand.',
    ifInfo: 'Der Gateway-Zustand wurde nur protokolliert.',
  ),
  'gpu': StageExplanation(
    what:
        'Der Nachweis der Grafikkarte (NVIDIA), auf der das Modell rechnet. '
        'Optional, in den Einstellungen zuschaltbar.',
    ifPass: 'NVIDIA bestätigt die geschützte GPU.',
    ifInfo:
        'Die GPU wurde nicht über NVIDIA geprüft, weil die Prüfung in den '
        'Einstellungen aus ist.',
  ),
  'receipt.fetch': StageExplanation(
    what: 'Der Abruf der signierten Quittung zu dieser Antwort.',
    ifPass: 'Der Anbieter hat die Quittung geliefert.',
    ifInfo: 'Der Abruf wurde nur protokolliert.',
  ),
  'receipt.signature': StageExplanation(
    what: 'Die Signatur der Quittung.',
    ifPass: 'Die Quittung stammt aus der geprüften Umgebung.',
    ifInfo: 'Die Signatur wurde nur protokolliert.',
  ),
  'receipt.binding': StageExplanation(
    what: 'Ob die Quittung zur geprüften Sitzung gehört.',
    ifPass: 'Quittung und Sitzung passen zusammen.',
    ifInfo: 'Die Bindung wurde nur protokolliert.',
  ),
  'receipt.request': StageExplanation(
    what: 'Die Prüfsumme der Anfrage in der Quittung gegen das, was gesendet wurde.',
    ifPass: 'Der Anbieter hat genau deine Anfrage erhalten.',
    ifInfo: 'Die Prüfsumme wurde nur protokolliert.',
  ),
  'receipt.response': StageExplanation(
    what: 'Die Prüfsumme der Antwort in der Quittung gegen das Empfangene.',
    ifPass: 'Die Antwort wurde unterwegs nicht verändert.',
    ifInfo: 'Die Prüfsumme wurde nur protokolliert.',
  ),
  'receipt.upstream': StageExplanation(
    what:
        'Ob das Gateway bestätigt, dass das Modell dahinter in einer '
        'geprüften Umgebung lief.',
    ifPass: 'Auch das Modell hinter dem Gateway wurde nachweislich geprüft.',
    ifInfo: 'Die Upstream-Prüfung wurde nur protokolliert.',
  ),
  'receipt.upstream.tcb': StageExplanation(
    what: 'Der Sicherheitsstand der Plattform hinter dem Gateway.',
    ifPass: 'Auch diese Plattform ist auf aktuellem Stand.',
    ifInfo: 'Der Stand wurde nur protokolliert.',
  ),
  'receipt.events': StageExplanation(
    what: 'Ob die Quittung alle erforderlichen Ereignisse enthält.',
    ifPass: 'Die Quittung ist vollständig.',
    ifInfo: 'Die Ereignisse wurden nur protokolliert.',
  ),
};
