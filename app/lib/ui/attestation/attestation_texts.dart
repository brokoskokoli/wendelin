import 'package:wendelin_core/wendelin_core.dart';

import '../design/design.dart';

/// What the user reads about the TEE check of one answer (WP52): a short
/// label for the shield and, for a non-green result, a title and an
/// explanation that tells apart a pending operator update from a
/// manipulation.
final class AttestationMessage {
  /// Creates the message.
  const AttestationMessage({
    required this.status,
    required this.label,
    this.title,
    this.text,
    this.canRecheck = true,
  });

  /// Symbol (colour + shape).
  final CheckStatus status;

  /// Short label next to the shield and for screen readers.
  final String label;

  /// Title of the warning card (red only).
  final String? title;

  /// Explanation of the warning card (red only).
  final String? text;

  /// Whether „Neu prüfen“ makes sense (not for GPU results, which only
  /// ask before the next request).
  final bool canRecheck;
}

/// Reason codes of a failed check (`StageResult` codes, WP46).
abstract final class AttestationReason {
  /// The operator's platform security update is pending.
  static const tcbOutOfDate = 'upstream_tcb_out_of_date';

  /// Intel advises the operator to restart the TEE.
  static const relaunchAdvised = 'tcb_relaunch_advised';

  /// The platform of the operator is revoked.
  static const tcbRevoked = 'upstream_tcb_revoked';

  /// The upstream session document does not match the receipt.
  static const sessionMismatch = 'upstream_session_mismatch';

  /// The gateway does not know the receipt (not written yet, expired).
  static const receiptNotFound = 'receipt_not_found';

  /// The receipt endpoint could not be reached (network, server error).
  static const receiptUnreachable = 'receipt_unreachable';

  /// The gateway refused the receipt request (key, rate limit).
  static const receiptRejected = 'receipt_rejected';

  /// The answer carried no receipt id.
  static const receiptMissing = 'receipt_missing';

  /// NVIDIA rejected the GPU evidence.
  static const gpuFailed = 'gpu_failed';

  /// NVIDIA could not be reached.
  static const gpuUnavailable = 'gpu_unavailable';
}

/// The wording for [status] with [reasonCode].
AttestationMessage attestationMessage(
  AttestationStatus status, {
  String? reasonCode,
}) {
  switch (status) {
    case AttestationStatus.green:
      return const AttestationMessage(status: CheckStatus.ok, label: 'geprüft');
    case AttestationStatus.yellow:
      return const AttestationMessage(
        status: CheckStatus.pending,
        label: 'wird geprüft',
      );
    case AttestationStatus.unconfirmed:
      return switch (reasonCode) {
        AttestationReason.receiptNotFound => _unconfirmed(
          'Quittung nicht gefunden',
          'Der Anbieter kennt die Quittung dieser Antwort nicht (noch nicht '
              'geschrieben oder abgelaufen).',
        ),
        AttestationReason.receiptMissing => _unconfirmed(
          'Quittung fehlt',
          'Der Anbieter hat zu dieser Antwort keine Quittungs-Kennung '
              'geliefert.',
        ),
        _ => _unconfirmed(
          'Quittung nicht erreichbar',
          'Die Quittung dieser Antwort konnte wegen eines Netz- oder '
              'Serverfehlers nicht abgerufen werden.',
        ),
      };
    case AttestationStatus.red:
      return switch (reasonCode) {
        AttestationReason.tcbOutOfDate => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'Prüfung fehlgeschlagen',
          title: 'Sicherheits-Update beim Betreiber ausstehend',
          text:
              'Die Hardware, auf der das Modell läuft, hat ein '
              'Sicherheits-Update des Herstellers noch nicht eingespielt. '
              'Das ist kein Hinweis auf eine Manipulation, schwächt aber '
              'den Schutz. Der Betreiber muss aktualisieren. Prüfe später '
              'erneut und sende bis dahin nichts Vertrauliches.',
        ),
        AttestationReason.relaunchAdvised => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'Prüfung fehlgeschlagen',
          title: 'Neustart der TEE beim Betreiber empfohlen',
          text:
              'Der Hersteller empfiehlt dem Betreiber, die geschützte '
              'Umgebung neu zu starten, damit ein Sicherheits-Update '
              'wirksam wird. Das ist kein Hinweis auf eine Manipulation. '
              'Prüfe später erneut.',
        ),
        AttestationReason.tcbRevoked => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'Prüfung fehlgeschlagen',
          title: 'Plattform des Betreibers zurückgezogen',
          text:
              'Der Hersteller hat die Hardware-Plattform des Betreibers als '
              'unsicher zurückgezogen. Sende nichts Vertrauliches, bis der '
              'Betreiber sie ersetzt hat.',
        ),
        AttestationReason.sessionMismatch => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'Prüfung fehlgeschlagen',
          title: 'Möglicher Manipulationsversuch',
          text:
              'Der Nachweis der Sitzung passt nicht zur signierten Quittung '
              'dieser Antwort. Vertraue der Antwort nicht. Der Anbieter ist '
              'gesperrt, bis du ihn neu prüfst.',
        ),
        AttestationReason.receiptRejected => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'Quittung abgelehnt',
          title: 'Quittungsabruf vom Anbieter abgelehnt',
          text:
              'Der Anbieter hat den Abruf der Quittung abgelehnt (zum '
              'Beispiel wegen zu vieler Anfragen). Die '
              'Antwort ist nicht bestätigt, es gibt aber keinen Hinweis auf '
              'eine Manipulation. Prüfe den Anbieter neu.',
        ),
        AttestationReason.gpuFailed => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'GPU-Prüfung fehlgeschlagen',
          title: 'GPU-Prüfung fehlgeschlagen',
          text:
              'NVIDIA hat die GPU-Nachweise nicht bestätigt, oder sie '
              'passen nicht zu unserer Anfrage. Die nächste Anfrage an '
              'dieses Modell wird vorher geprüft.',
          canRecheck: false,
        ),
        AttestationReason.gpuUnavailable => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'GPU-Prüfung nicht möglich',
          title: 'GPU-Prüfung nicht möglich',
          text:
              'NVIDIA war nicht erreichbar. Die nächste Anfrage an dieses '
              'Modell wird vorher geprüft.',
          canRecheck: false,
        ),
        _ => const AttestationMessage(
          status: CheckStatus.failed,
          label: 'Prüfung fehlgeschlagen',
          title: 'Prüfung fehlgeschlagen',
          text:
              'Die Antwort konnte nicht als unverändert aus der geprüften '
              'Umgebung bestätigt werden, zum Beispiel wegen eines '
              'Signaturfehlers oder abweichender Prüfsummen. Das kann auf '
              'eine Manipulation hindeuten. Vertraue der Antwort nicht. Der '
              'Anbieter ist gesperrt, bis du ihn neu prüfst.',
        ),
      };
  }
}

AttestationMessage _unconfirmed(String title, String cause) =>
    AttestationMessage(
      status: CheckStatus.neutral,
      label: 'nicht bestätigt',
      title: title,
      text:
          '$cause Ob die Antwort aus der geprüften Umgebung stammt, ist '
          'unbestätigt. Es wurde aber auch kein Fehler festgestellt, der '
          'Anbieter bleibt nutzbar. Aktionen, die auf die geprüfte Antwort '
          'warten, laufen nicht. Prüfe den Anbieter neu.',
    );

/// German name of a check stage id for the log (`quote` → „TDX-Quote“).
String stageLabel(String stage) => switch (stage) {
  'quote' => 'TDX-Quote (DCAP)',
  'tcb' => 'Plattform-Sicherheitsstand (TCB)',
  'nonce' => 'Nonce gebunden',
  'keyset.digest' => 'Schlüsselsatz (Digest)',
  'keyset.endorsement' => 'Schlüsselsatz-Signatur',
  'freshness' => 'Frische',
  'eventlog' => 'Ereignisprotokoll',
  'compose' => 'Compose-Hash',
  'provenance' => 'Herkunft (Commit)',
  'tls.spki' => 'TLS-Verbindung geprüft',
  'e2ee.key' => 'E2EE-Schlüssel geprüft',
  'e2ee.request' => 'Verschlüsselung der Anfrage',
  'e2ee.response' => 'Entschlüsselung der Antwort',
  'e2ee.keyset' => 'Schlüsselsatz der Antwort',
  'gpu' => 'GPU-Evidenz',
  'receipt.fetch' => 'Quittung abgerufen',
  'receipt.signature' => 'Quittungs-Signatur',
  'receipt.binding' => 'Quittung an Sitzung gebunden',
  'receipt.request' => 'Hash der Anfrage',
  'receipt.response' => 'Hash der Antwort',
  'receipt.upstream' => 'Upstream-Prüfung',
  'receipt.upstream.tcb' => 'Upstream-Sicherheitsstand',
  'receipt.events' => 'Quittungs-Ereignisse',
  _ => stage,
};

/// German text of a stage result name (`pass` → „bestanden“).
String stageResultLabel(String result) => switch (result) {
  'pass' => 'bestanden',
  'fail' => 'fehlgeschlagen',
  'warn' => 'Hinweis',
  'unavailable' => 'nicht abrufbar',
  'info' => 'nur protokolliert',
  _ => result,
};

/// Symbol of a stage result name; `null` for `info`.
CheckStatus? stageResultStatus(String result) => switch (result) {
  'pass' => CheckStatus.ok,
  'fail' => CheckStatus.failed,
  'warn' || 'unavailable' => CheckStatus.pending,
  _ => null,
};

/// Short note on the stage „Ende-zu-Ende-verschlüsselt“: where the
/// encryption ends (ADR 0018). `null` for other stages.
String? stageExplanation(String stage) => switch (stage) {
  'e2ee.key' =>
    'Alle Inhalte werden mit diesem geprüften Schlüssel verschlüsselt. '
        'Die Verschlüsselung endet im Gateway des Anbieters (geprüfte '
        'Enklave), nicht im Modell selbst.',
  _ => null,
};
