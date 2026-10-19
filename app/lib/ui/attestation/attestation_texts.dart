import 'package:wendelin_core/wendelin_core.dart';

import '../../l10n/l10n.dart';
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

/// Shield label of a green answer with a restriction the user has not
/// accepted yet (WP78).
String restrictionOpenLabel(AppLocalizations l) => l.attRestrictionOpen;

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

  /// The release is older than the highest one ever verified (K59).
  static const releaseRollback = 'release_rollback';

  /// The stored release floor is damaged; the check stays locked.
  static const releaseFloorCorrupt = 'release_floor_corrupt';

  /// NVIDIA rejected the GPU evidence.
  static const gpuFailed = 'gpu_failed';

  /// NVIDIA could not be reached.
  static const gpuUnavailable = 'gpu_unavailable';
}

/// The wording for [status] with [reasonCode].
///
/// [detail] is the secret-free reason of the check; for a failed GPU check
/// it is shown as „Grund“ (HTTP status, timeout, no evidence, …; WP77).
AttestationMessage attestationMessage(
  AppLocalizations l,
  AttestationStatus status, {
  String? reasonCode,
  String? detail,
}) {
  switch (status) {
    case AttestationStatus.green:
      return AttestationMessage(status: CheckStatus.ok, label: l.checkStatusOk);
    case AttestationStatus.yellow:
      return AttestationMessage(
        status: CheckStatus.pending,
        label: l.attChecking,
      );
    case AttestationStatus.unconfirmed:
      return switch (reasonCode) {
        AttestationReason.receiptNotFound => _unconfirmed(
          l,
          l.attReceiptNotFound,
          l.attReceiptNotFoundText,
        ),
        AttestationReason.receiptMissing => _unconfirmed(
          l,
          l.attReceiptMissing,
          l.attReceiptMissingText,
        ),
        _ => _unconfirmed(
          l,
          l.attReceiptUnreachable,
          l.attReceiptUnreachableText,
        ),
      };
    case AttestationStatus.red:
      return switch (reasonCode) {
        AttestationReason.tcbOutOfDate => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attTcbTitle,
          text: l.attTcbText,
        ),
        AttestationReason.relaunchAdvised => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attRelaunchTitle,
          text: l.attRelaunchText,
        ),
        AttestationReason.tcbRevoked => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attRevokedTitle,
          text: l.attRevokedText,
        ),
        AttestationReason.sessionMismatch => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attMismatchTitle,
          text: l.attMismatchText,
        ),
        AttestationReason.receiptRejected => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attReceiptRejectedLabel,
          title: l.attReceiptRejectedTitle,
          text: l.attReceiptRejectedText,
        ),
        AttestationReason.releaseRollback => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attRollbackTitle,
          text: l.attRollbackText,
        ),
        AttestationReason.releaseFloorCorrupt => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attFloorCorruptTitle,
          text: l.attFloorCorruptText,
          canRecheck: false,
        ),
        AttestationReason.gpuFailed => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attGpuFailedLabel,
          title: l.attGpuFailedTitle,
          text: l.attGpuFailedText(_gpuReason(l, detail)),
          canRecheck: false,
        ),
        AttestationReason.gpuUnavailable => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attGpuUnavailableLabel,
          title: l.attGpuUnavailableTitle,
          text: l.attGpuUnavailableText(_gpuReason(l, detail)),
          canRecheck: false,
        ),
        _ => AttestationMessage(
          status: CheckStatus.failed,
          label: l.attCheckFailed,
          title: l.attCheckFailed,
          text: l.attFailedText,
        ),
      };
  }
}

/// „ Grund: …“ from the message of a request stopped by the GPU check
/// (`GPU-Prüfung nicht bestanden (Grund [Kategorie]); Anfrage nicht
/// gesendet`); empty if there is none.
String gpuBlockReason(AppLocalizations l, String message) {
  final m = RegExp(r'\((.*?)(?: \[[a-z0-9_]+\])?\); Anfrage')
      .firstMatch(message);
  final reason = m?.group(1);
  if (reason == null || reason.isEmpty) return '';
  return l.attReasonLead(reason, reason.endsWith('.') ? '' : '.');
}

/// „ Grund: …“ from the stored detail (`GPU-Prüfung: …` / `gpu: …`).
String _gpuReason(AppLocalizations l, String? detail) {
  if (detail == null || detail.trim().isEmpty) return '';
  final text = detail.replaceFirst(RegExp(r'^(GPU-Prüfung|gpu): '), '');
  return l.attStoredReason(text, text.endsWith('.') ? '' : '.');
}

AttestationMessage _unconfirmed(
  AppLocalizations l,
  String title,
  String cause,
) => AttestationMessage(
  status: CheckStatus.neutral,
  label: l.attUnconfirmed,
  title: title,
  text: l.attUnconfirmedText(cause),
);

/// German name of a check stage id for the log (`quote` → „TDX-Quote“).
String stageLabel(AppLocalizations l, String stage) => switch (stage) {
  'quote' => l.attSQuote,
  'tcb' => l.attSTcb,
  'nonce' => l.attSNonce,
  'keyset.digest' => l.attSKeysetDigest,
  'keyset.endorsement' => l.attSKeysetSignature,
  'freshness' => l.attSFreshness,
  'eventlog' => l.attSEventLog,
  'compose' => l.attSCompose,
  'provenance' => l.attSProvenance,
  'tls.spki' => l.attSTls,
  'e2ee.key' => l.attSE2eeKey,
  'e2ee.request' => l.attSE2eeRequest,
  'e2ee.response' => l.attSE2eeResponse,
  'e2ee.keyset' => l.attSE2eeKeyset,
  'gateway' => l.attSGateway,
  'gpu' => l.attSGpu,
  'gpu.evidence' => l.attSGpuEvidence,
  'snp.report' => l.attSSnpReport,
  'snp.chain' => l.attSSnpChain,
  'snp.policy' => l.attSSnpPolicy,
  'bind.hpke' => l.attSBindHpke,
  'sigstore.release' => l.attSSigstore,
  'measurement' => l.attSMeasurement,
  'release.floor' => l.attSReleaseFloor,
  'receipt.none' => l.attSNoReceipt,
  'receipt.fetch' => l.attSReceiptFetch,
  'receipt.signature' => l.attSReceiptSignature,
  'receipt.binding' => l.attSReceiptBinding,
  'receipt.request' => l.attSReceiptRequest,
  'receipt.response' => l.attSReceiptResponse,
  'receipt.upstream' => l.attSUpstream,
  'receipt.upstream.tcb' => l.attSUpstreamTcb,
  'receipt.events' => l.attSReceiptEvents,
  _ => stage,
};

/// German text of a stage result name (`pass` → „bestanden“).
String stageResultLabel(AppLocalizations l, String result) => switch (result) {
  'pass' => l.stageResultPass,
  'fail' => l.stageResultFail,
  'warn' => l.attResultWarn,
  'unavailable' => l.attResultUnavailable,
  'info' => l.attResultInfo,
  _ => result,
};

/// Symbol of a stage result name; every result has one (`info` → grey).
CheckStatus stageResultStatus(String result) => switch (result) {
  'pass' => CheckStatus.ok,
  'fail' => CheckStatus.failed,
  'warn' || 'unavailable' => CheckStatus.pending,
  _ => CheckStatus.info,
};

/// Short note on the stage „Ende-zu-Ende-verschlüsselt“: where the
/// encryption ends (ADR 0018). `null` for other stages.
String? stageExplanation(AppLocalizations l, String stage) => switch (stage) {
  'e2ee.key' => l.attE2eeKeyNote,
  _ => null,
};
