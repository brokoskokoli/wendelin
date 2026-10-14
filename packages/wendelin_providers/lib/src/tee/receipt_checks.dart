import 'dart:typed_data';

import 'attestation_crypto.dart';
import 'attestation_types.dart';
import 'codec.dart';
import 'gateway_documents.dart';

/// The checks of one receipt against the attested session and the exact
/// bytes of the exchange (concept step 5). Each check is its own stage;
/// none hides another.
final class ReceiptChecks {
  /// Creates the checks.
  ReceiptChecks(this.crypto, {this.expectUpstreamEnforced = true});

  /// Hash and signature primitives.
  final AttestationCrypto crypto;

  /// Require `upstream.verified.required == true`.
  final bool expectUpstreamEnforced;

  /// Runs all receipt stages.
  List<StageResult> run(
    GatewayReceipt r,
    AttestedSession session,
    Uint8List requestBytes,
    Uint8List responseBytes,
  ) => [
    _events(r),
    _signature(r, session),
    _binding(r, session),
    _hash(
      AttestationStage.requestHash,
      r.event('request.received'),
      requestBytes,
    ),
    _hash(
      AttestationStage.responseHash,
      r.event('response.returned'),
      responseBytes,
    ),
    _upstream(r.event('upstream.verified')),
  ];

  static const _required = [
    'request.received',
    'route.selected',
    'upstream.verified',
    'response.returned',
  ];

  StageResult _events(GatewayReceipt r) {
    final missing = [
      for (final t in _required)
        if (r.event(t) == null) t,
    ];
    return missing.isEmpty
        ? const StageResult.pass(AttestationStage.receiptEvents)
        : StageResult.fail(
            AttestationStage.receiptEvents,
            'Ereignis fehlt: ${missing.join(', ')}',
          );
  }

  StageResult _signature(GatewayReceipt r, AttestedSession session) {
    final key = session.receiptKeys[r.keyId];
    if (key == null) {
      return StageResult.fail(
        AttestationStage.receiptSignature,
        'Schlüssel "${r.keyId}" nicht im Keyset',
      );
    }
    try {
      final ok = crypto.verifyEd25519(
        key,
        r.signedBytes(),
        AttestCodec.unhex(r.signature),
      );
      return ok
          ? const StageResult.pass(AttestationStage.receiptSignature)
          : const StageResult.fail(
              AttestationStage.receiptSignature,
              'Signatur ungültig',
            );
    } on FormatException {
      return const StageResult.fail(
        AttestationStage.receiptSignature,
        'Signatur unlesbar',
      );
    }
  }

  StageResult _binding(GatewayReceipt r, AttestedSession session) {
    if (r.keysetDigest != session.keysetDigest) {
      return const StageResult.fail(
        AttestationStage.receiptBinding,
        'Keyset der Quittung weicht von der Attestierung ab',
      );
    }
    final id = session.workloadId;
    if (id != null && r.workloadId != id) {
      return const StageResult.fail(
        AttestationStage.receiptBinding,
        'workload_id weicht ab',
      );
    }
    return const StageResult.pass(AttestationStage.receiptBinding);
  }

  /// Compares `wire_hash` (if present, else `body_hash`) of [event] with the
  /// SHA-256 of [bytes].
  StageResult _hash(
    AttestationStage stage,
    ReceiptEvent? event,
    Uint8List bytes,
  ) {
    if (event == null) {
      return StageResult.fail(stage, 'Ereignis fehlt');
    }
    final expected = event.raw['wire_hash'] ?? event.raw['body_hash'];
    if (expected is! String) {
      return StageResult.fail(stage, 'Hash fehlt');
    }
    return AttestCodec.prefixed(crypto.sha256(bytes)) == expected
        ? StageResult.pass(stage)
        : StageResult.fail(stage, 'Hash passt nicht zu den Bytes');
  }

  StageResult _upstream(ReceiptEvent? event) {
    const s = AttestationStage.upstream;
    if (event == null) return const StageResult.fail(s, 'Ereignis fehlt');
    if (event.raw['result'] != 'verified') {
      return StageResult.fail(s, 'Ergebnis: ${event.raw['result']}');
    }
    if (expectUpstreamEnforced && event.raw['required'] != true) {
      return const StageResult.fail(
        s,
        'Upstream-Prüfung nicht erzwungen (required: false)',
      );
    }
    return const StageResult.pass(s);
  }
}
