import 'dart:convert';
import 'dart:typed_data';

import 'attestation_types.dart';
import 'codec.dart';

/// A required field is missing or has the wrong type; [stage] is the check
/// that cannot run because of it.
final class AttestationFormatException implements Exception {
  /// Creates the exception.
  const AttestationFormatException(this.stage, this.message);

  /// The affected stage.
  final AttestationStage stage;

  /// What is wrong (field name, never content).
  final String message;

  @override
  String toString() => 'AttestationFormatException(${stage.id}): $message';
}

T _req<T>(Map<String, Object?> m, String key, AttestationStage stage) {
  final v = m[key];
  if (v is T) return v;
  throw AttestationFormatException(stage, 'Pflichtfeld "$key" fehlt');
}

/// Hex public key with id, from the keyset.
final class KeysetKey {
  /// Creates a key.
  const KeysetKey(this.keyId, this.algo, this.publicKey);

  /// `key_id`.
  final String keyId;

  /// `algo`.
  final String algo;

  /// Hex public key.
  final String publicKey;
}

/// `attestation.workload_keyset` of the gateway attestation.
final class WorkloadKeyset {
  /// Parses [json]; keeps the raw map for canonicalisation.
  factory WorkloadKeyset.parse(Map<String, Object?> json) {
    const s = AttestationStage.keysetDigest;
    List<KeysetKey> keys(String name) => [
      for (final k in _req<List<Object?>>(json, name, s))
        if (k is Map<String, Object?>)
          KeysetKey(
            _req<String>(k, 'key_id', s),
            _req<String>(k, 'algo', s),
            _req<String>(k, 'public_key', s),
          ),
    ];
    final tls = <String, String>{
      if (json['tls_public_keys'] case final List<Object?> list)
        for (final k in list)
          if (k is Map<String, Object?> &&
              k['domain'] is String &&
              k['spki_sha256'] is String)
            k['domain']! as String: k['spki_sha256']! as String,
    };
    return WorkloadKeyset._(
      json,
      _req<int>(json, 'not_after', AttestationStage.freshness),
      keys('receipt_signing_keys'),
      tls,
    );
  }

  const WorkloadKeyset._(
    this.raw,
    this.notAfterEpoch,
    this.receiptSigningKeys,
    this.tlsSpkiByDomain,
  );

  /// The keyset as delivered (input of the digest).
  final Map<String, Object?> raw;

  /// `not_after` in Unix seconds.
  final int notAfterEpoch;

  /// `receipt_signing_keys`.
  final List<KeysetKey> receiptSigningKeys;

  /// `tls_public_keys`: domain → SPKI SHA-256 hex.
  final Map<String, String> tlsSpkiByDomain;
}

/// One entry of the TDX event log (`evidence.event_log`).
final class TdxEvent {
  /// Creates an entry.
  const TdxEvent({
    required this.imr,
    required this.eventType,
    required this.digest,
    required this.event,
    required this.payload,
  });

  /// Measurement register index.
  final int imr;

  /// TCG event type.
  final int eventType;

  /// 48-byte digest as logged.
  final Uint8List digest;

  /// Event name (e.g. `compose-hash`).
  final String event;

  /// Payload bytes (decoded hex).
  final Uint8List payload;
}

/// Parsed `GET /v1/aci/attestation` document. Unknown fields are ignored.
final class GatewayAttestation {
  /// Parses the document; throws [AttestationFormatException].
  factory GatewayAttestation.parse(Map<String, Object?> json) {
    const q = AttestationStage.quote;
    final att = _req<Map<String, Object?>>(json, 'attestation', q);
    final ev = _req<Map<String, Object?>>(att, 'evidence', q);
    final prov = att['source_provenance'];
    final fresh = json['freshness'] ?? att['freshness'];
    final binding = ev['downstream_tls_binding'];
    List<TdxEvent> events;
    try {
      final raw = ev['event_log'];
      final list = raw is String ? jsonDecode(raw) : raw;
      events = [
        for (final e in list as List<Object?>)
          if (e is Map<String, Object?>)
            TdxEvent(
              imr: e['imr']! as int,
              eventType: e['event_type']! as int,
              digest: AttestCodec.unhex(e['digest']! as String),
              event: (e['event'] as String?) ?? '',
              payload: AttestCodec.unhex((e['event_payload'] as String?) ?? ''),
            ),
      ];
    } on Object {
      throw const AttestationFormatException(
        AttestationStage.eventLog,
        'event_log unlesbar',
      );
    }
    final String quoteHex;
    final quoteField = _req<String>(ev, 'quote', q);
    quoteHex = quoteField;
    Uint8List quote;
    try {
      quote = AttestCodec.unhex(quoteHex);
    } on FormatException {
      try {
        quote = base64Decode(quoteHex);
      } on FormatException {
        throw const AttestationFormatException(q, 'quote unlesbar');
      }
    }
    return GatewayAttestation._(
      apiVersion: _req<String>(json, 'api_version', q),
      keysetDigest: _req<String>(json, 'workload_keyset_digest', q),
      keyset: WorkloadKeyset.parse(
        _req<Map<String, Object?>>(att, 'workload_keyset', q),
      ),
      reportData: _req<String>(
        att,
        'report_data',
        AttestationStage.nonceBinding,
      ),
      quote: quote,
      eventLog: events,
      appCompose: _req<String>(ev, 'app_compose', AttestationStage.composeHash),
      repoCommit: prov is Map<String, Object?>
          ? prov['repo_commit'] as String?
          : null,
      workloadId: (json['workload_id'] ?? att['workload_id']) as String?,
      staleAfterEpoch: fresh is Map<String, Object?>
          ? fresh['stale_after'] as int?
          : null,
      downstreamTlsDomain: binding is Map<String, Object?>
          ? binding['domain'] as String?
          : null,
      downstreamTlsSpki: binding is Map<String, Object?>
          ? binding['spki_sha256'] as String?
          : null,
      hasEndorsement: att.containsKey('keyset_endorsement'),
    );
  }

  const GatewayAttestation._({
    required this.apiVersion,
    required this.keysetDigest,
    required this.keyset,
    required this.reportData,
    required this.quote,
    required this.eventLog,
    required this.appCompose,
    required this.repoCommit,
    required this.workloadId,
    required this.staleAfterEpoch,
    required this.downstreamTlsDomain,
    required this.downstreamTlsSpki,
    required this.hasEndorsement,
  });

  /// `api_version`.
  final String apiVersion;

  /// Advertised `workload_keyset_digest` (`sha256:<hex>`).
  final String keysetDigest;

  /// The keyset.
  final WorkloadKeyset keyset;

  /// `report_data` hex as delivered.
  final String reportData;

  /// Raw quote bytes.
  final Uint8List quote;

  /// Event log.
  final List<TdxEvent> eventLog;

  /// `app_compose` exactly as sent.
  final String appCompose;

  /// `source_provenance.repo_commit`, if present.
  final String? repoCommit;

  /// `workload_id`, if the API delivers one.
  final String? workloadId;

  /// `freshness.stale_after`, if present.
  final int? staleAfterEpoch;

  /// Domain of `downstream_tls_binding`.
  final String? downstreamTlsDomain;

  /// SPKI hash of `downstream_tls_binding`.
  final String? downstreamTlsSpki;

  /// Whether the document carries a `keyset_endorsement` field.
  final bool hasEndorsement;
}

/// One receipt event; the raw map keeps unknown fields.
final class ReceiptEvent {
  /// Creates an event.
  const ReceiptEvent(this.raw);

  /// Event map.
  final Map<String, Object?> raw;

  /// `type`.
  String get type => (raw['type'] as String?) ?? '';
}

/// Parsed receipt (`GET /v1/aci/receipts/{id}`). Unknown fields ignored.
final class GatewayReceipt {
  /// Parses the receipt; throws [AttestationFormatException].
  factory GatewayReceipt.parse(Map<String, Object?> json) {
    const s = AttestationStage.receiptEvents;
    final log = _req<List<Object?>>(json, 'event_log', s);
    return GatewayReceipt._(
      json,
      [
        for (final e in log)
          if (e is Map<String, Object?>) ReceiptEvent(e),
      ],
      _req<String>(json, 'signature', AttestationStage.receiptSignature),
      _req<String>(json, 'key_id', AttestationStage.receiptSignature),
      _req<String>(
        json,
        'workload_keyset_digest',
        AttestationStage.receiptBinding,
      ),
      json['workload_id'] as String?,
    );
  }

  const GatewayReceipt._(
    this.raw,
    this.events,
    this.signature,
    this.keyId,
    this.keysetDigest,
    this.workloadId,
  );

  /// The receipt as delivered.
  final Map<String, Object?> raw;

  /// `event_log`.
  final List<ReceiptEvent> events;

  /// Signature hex.
  final String signature;

  /// Signing key id.
  final String keyId;

  /// Bound keyset digest.
  final String keysetDigest;

  /// `workload_id`, if present.
  final String? workloadId;

  /// The first event of [type], if any.
  ReceiptEvent? event(String type) {
    for (final e in events) {
      if (e.type == type) return e;
    }
    return null;
  }

  /// The bytes the signature covers: canonical JSON of the receipt without
  /// `signature`.
  Uint8List signedBytes() => AttestCodec.jcsBytes({
    for (final e in raw.entries)
      if (e.key != 'signature') e.key: e.value,
  });
}

/// Parsed upstream session (`GET /v1/aci/sessions/{session_id}`): only the
/// TCB claims. Unknown fields ignored.
final class GatewaySession {
  /// Parses the session; throws [AttestationFormatException].
  factory GatewaySession.parse(Map<String, Object?> json) {
    const s = AttestationStage.upstreamTcb;
    final claims = _req<Map<String, Object?>>(json, 'claims', s);
    final extra = claims['extra'];
    final upToDate = claims['tcb_up_to_date'];
    return GatewaySession._(
      raw: json,
      upToDateStatus: upToDate is Map<String, Object?>
          ? upToDate['status'] as String?
          : null,
      tcbStatus: extra is Map<String, Object?>
          ? extra['tcb_status'] as String?
          : null,
    );
  }

  const GatewaySession._({
    required this.raw,
    this.upToDateStatus,
    this.tcbStatus,
  });

  /// The whole document; `sha256(JCS(raw))` is the `session_id` the signed
  /// receipt names.
  final Map<String, Object?> raw;

  /// `claims.tcb_up_to_date.status` (`refuted`, `asserted`, …).
  final String? upToDateStatus;

  /// `claims.extra.tcb_status` (`UpToDate`, `OutOfDate`, …).
  final String? tcbStatus;
}
