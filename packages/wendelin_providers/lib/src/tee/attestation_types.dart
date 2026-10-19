import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// One check of the verification, each reported on its own for the audit
/// log. [name] is the stable id used in logs (`Wendelin/attest:`) and JSON.
enum AttestationStage {
  /// TDX quote signature chain against the collateral.
  quote('quote'),

  /// Platform TCB status.
  tcb('tcb'),

  /// `report_data` binds our nonce (and the advertised keyset digest).
  nonceBinding('nonce'),

  /// Advertised keyset digest equals the digest of the delivered keyset.
  keysetDigest('keyset.digest'),

  /// Keyset endorsement (the gateway API has none; the binding runs over
  /// `report_data`, see ADR 0014).
  keysetEndorsement('keyset.endorsement'),

  /// `not_after` / `stale_after` lie in the future.
  freshness('freshness'),

  /// RTMR3 replay of the event log equals the quote.
  eventLog('eventlog'),

  /// `sha256(app_compose)` equals the measured compose hash.
  composeHash('compose'),

  /// `repo_commit` against the list of trusted commits.
  provenance('provenance'),

  /// TLS SPKI of the endpoint against the keyset.
  tlsSpki('tls.spki'),

  /// The attested keyset has an E2EE key of the suite we speak (WP62).
  e2eeKey('e2ee.key'),

  /// Encrypting the request failed (only logged on failure).
  e2eeRequest('e2ee.request'),

  /// Decrypting the response failed (only logged on failure).
  e2eeResponse('e2ee.response'),

  /// The keyset of the response did not match (only logged on failure).
  e2eeKeyset('e2ee.keyset'),

  /// The gateway's own TDX quote (NEAR AI, WP75): bound to the nonce, TCB
  /// shown; it only sees ciphertext, so an old TCB is a hint, not a block.
  gateway('gateway'),

  /// NVIDIA NRAS check of the GPU evidence.
  gpu('gpu'),

  /// The provider delivers no GPU evidence for the model (WP82): NVIDIA
  /// cannot check it; a restriction of the provider, not a failure.
  gpuEvidence('gpu.evidence'),

  /// Tinfoil (WP76d): SEV-SNP report readable, VCEK belongs to the chip and
  /// the TCB of the report, ECDSA P-384 signature valid.
  snpReport('snp.report'),

  /// Tinfoil: VCEK -> ASK -> ARK valid, ARK pinned.
  snpChain('snp.chain'),

  /// Tinfoil: no debug guest, VMPL 0, VCEK-signed, TCB minimum met.
  snpPolicy('snp.policy'),

  /// Tinfoil: the HPKE key served by the router is the one in
  /// `report_data[32..64]` of the verified report.
  bindHpke('bind.hpke'),

  /// Tinfoil: Sigstore verification of the signed release (DSSE, Fulcio
  /// chain, identity, Rekor).
  sigstoreRelease('sigstore.release'),

  /// Tinfoil: the measurement of the report is the one of the latest signed
  /// release.
  measurement('measurement'),

  /// Tinfoil: the release is not older than the highest one seen before
  /// (downgrade protection, K59).
  releaseFloor('release.floor'),

  /// Tinfoil: there is no receipt per answer (information, ADR 0020).
  noReceipt('receipt.none'),

  /// Receipt could be fetched.
  receiptFetch('receipt.fetch'),

  /// Ed25519 signature of the receipt.
  receiptSignature('receipt.signature'),

  /// Receipt is bound to the attested keyset (and workload id).
  receiptBinding('receipt.binding'),

  /// `request.received` body hash equals the bytes we sent.
  requestHash('receipt.request'),

  /// `response.returned` hash equals the bytes we received.
  responseHash('receipt.response'),

  /// `upstream.verified` with result `verified`.
  upstream('receipt.upstream'),

  /// TCB status of the upstream's TEE session (`/aci/sessions/{id}`).
  upstreamTcb('receipt.upstream.tcb'),

  /// The receipt contains the required events.
  receiptEvents('receipt.events');

  const AttestationStage(this.id);

  /// Stable id.
  final String id;
}

/// Result of one stage.
enum StageOutcome {
  /// Passed.
  pass,

  /// Passed with a hint to the user (e.g. TCB needs hardening).
  warn,

  /// Failed: the data is wrong or manipulated.
  fail,

  /// Could not be completed (network); may be retried.
  unavailable,

  /// Not applicable or only logged (e.g. empty list of trusted commits).
  info,
}

/// Outcome of a stage with a secret-free [detail].
@immutable
final class StageResult {
  /// Creates a result.
  const StageResult(this.stage, this.outcome, [this.detail, this.code]);

  /// A passed stage.
  const StageResult.pass(this.stage, [this.detail])
    : outcome = StageOutcome.pass,
      code = null;

  /// A failed stage; [code] marks a special reason (see [code]).
  const StageResult.fail(this.stage, this.detail, {this.code})
    : outcome = StageOutcome.fail;

  /// The stage.
  final AttestationStage stage;

  /// The result.
  final StageOutcome outcome;

  /// Reason or note (never prompt or receipt content).
  final String? detail;

  /// Stable reason code for failures that are not manipulation, e.g.
  /// [upstreamTcbOutOfDate]; `null` for ordinary failures.
  final String? code;

  /// Code: the upstream's platform TCB is out of date (the operator's
  /// security update is pending); not a forgery.
  static const upstreamTcbOutOfDate = 'upstream_tcb_out_of_date';

  /// Code: Intel advises relaunching the platform TEE (`TDRelaunchAdvised*`);
  /// the operator has to act, not a forgery.
  static const tcbRelaunchAdvised = 'tcb_relaunch_advised';

  /// Code: the upstream session document does not hash to the `session_id`
  /// the signed receipt names (manipulated or swapped document).
  static const upstreamSessionMismatch = 'upstream_session_mismatch';

  /// Code: the upstream's platform TCB is revoked.
  static const upstreamTcbRevoked = 'upstream_tcb_revoked';

  /// Code: the gateway does not know the receipt (HTTP 404: not yet written,
  /// expired or held by another instance); not a forgery.
  static const receiptNotFound = 'receipt_not_found';

  /// Code: the receipt endpoint could not be reached (network, timeout or a
  /// server error); not a forgery.
  static const receiptUnreachable = 'receipt_unreachable';

  /// Code: the gateway refused the receipt request (HTTP 400/401/403/429);
  /// not a forgery.
  static const receiptRejected = 'receipt_rejected';

  /// Code: the answer carried no receipt id.
  static const receiptMissing = 'receipt_missing';

  /// JSON for the audit log.
  Map<String, Object?> toJson() => {
    'stage': stage.id,
    'result': outcome.name,
    if (detail != null) 'detail': detail,
    if (code != null) 'code': code,
  };

  @override
  String toString() => '${stage.id}=${outcome.name}';
}

/// A public E2EE key of the attested keyset.
@immutable
final class E2eeKey {
  /// Creates a key.
  const E2eeKey({
    required this.keyId,
    required this.algo,
    required this.publicKey,
  });

  /// `key_id` (a label only; the key is chosen by [algo]).
  final String keyId;

  /// `algo`, the suite.
  final String algo;

  /// Raw public key.
  final Uint8List publicKey;
}

/// The attested state of a session, the basis for checking receipts.
@immutable
final class AttestedSession {
  /// Creates a session.
  const AttestedSession({
    required this.keysetDigest,
    required this.notAfter,
    required this.receiptKeys,
    required this.repoCommit,
    required this.composeHash,
    required this.attestedAt,
    this.workloadId,
    this.e2eeKey,
    this.ehbpKeyConfig,
    this.reportData,
  });

  /// Tinfoil: the key configuration (`/.well-known/hpke-keys`) that matches
  /// [reportData]; `null` for other providers.
  final Uint8List? ehbpKeyConfig;

  /// Tinfoil: `report_data` (64 bytes) of the verified SNP report: TLS pin
  /// ‖ HPKE key. The only source of both bindings.
  final Uint8List? reportData;

  /// The E2EE key of the attested keyset (suite of `E2eeProtocolV2`); every
  /// request is encrypted to it. `null` only in sessions of tests that do
  /// not speak E2EE: the provider then refuses to send.
  final E2eeKey? e2eeKey;

  /// `sha256:<hex>` of the keyset (the pin).
  final String keysetDigest;

  /// End of validity of the keyset.
  final DateTime notAfter;

  /// Receipt signing keys: `key_id` → Ed25519 public key.
  final Map<String, Uint8List> receiptKeys;

  /// Commit of the attested gateway (provenance), if given.
  final String? repoCommit;

  /// `sha256` hex of `app_compose`.
  final String composeHash;

  /// When the attestation was done.
  final DateTime attestedAt;

  /// Workload id if the API delivers one (it does not today).
  final String? workloadId;
}

/// How the attested state compares to the stored pin.
enum PinChange {
  /// Same keyset, commit and compose hash as pinned.
  none,

  /// Nothing pinned yet; the state was pinned now.
  first,

  /// The provider rolled out an update: the user is informed.
  changed,
}

/// Result of [AttestationVerifier.attest].
@immutable
final class AttestationResult {
  /// Creates a result.
  const AttestationResult({
    required this.status,
    required this.stages,
    this.session,
    this.notes = const [],
    this.pinChange = PinChange.none,
  });

  /// Traffic light of the session.
  final AttestationStatus status;

  /// Every stage that ran, in order.
  final List<StageResult> stages;

  /// Present if no stage failed (green).
  final AttestedSession? session;

  /// Hints for the user (TCB advisories, unlisted commit, …).
  final List<String> notes;

  /// Comparison with the stored pin (only for green results).
  final PinChange pinChange;

  /// First failed or unavailable stage, if any.
  StageResult? get firstProblem => stages
      .where(
        (s) =>
            s.outcome == StageOutcome.fail ||
            s.outcome == StageOutcome.unavailable,
      )
      .firstOrNull;
}

/// What identifies the receipt of one answer.
@immutable
final class ReceiptRef {
  /// Creates a reference.
  const ReceiptRef({required this.id, required this.session, this.alternateId});

  /// Value of the `x-receipt-id` header.
  final String id;

  /// The `id` (chat id) of the response body; the gateway accepts it as a
  /// receipt id as well, so it is tried when [id] is not found.
  final String? alternateId;

  /// The attested session that served the answer.
  final AttestedSession session;
}

/// Result of [AttestationVerifier.verifyReceipt].
@immutable
final class ReceiptResult {
  /// Creates a result.
  const ReceiptResult({
    required this.stages,
    required this.status,
    this.pinChanged = false,
    this.receiptId,
  });

  /// Every stage that ran.
  final List<StageResult> stages;

  /// Traffic light of this single attempt: red on any failure, yellow if
  /// only unavailable (the caller retries and turns the third into red).
  final AttestationStatus status;

  /// The receipt is bound to another keyset than the session: the provider
  /// rolled out an update. A new attestation is required.
  final bool pinChanged;

  /// The receipt id as checked.
  final String? receiptId;

  /// First failed or unavailable stage, if any.
  StageResult? get firstProblem => stages
      .where(
        (s) =>
            s.outcome == StageOutcome.fail ||
            s.outcome == StageOutcome.unavailable,
      )
      .firstOrNull;
}

/// Attestation of a TEE provider (concept: „TEE-Provider und Attestierung“).
abstract interface class AttestationVerifier {
  /// Attests the provider with a fresh nonce (once per session).
  Future<AttestationResult> attest();

  /// Verifies the receipt of one answer against the bytes we sent and
  /// received.
  Future<ReceiptResult> verifyReceipt(
    ReceiptRef ref,
    Uint8List requestBytes,
    Uint8List responseBytes,
  );
}
