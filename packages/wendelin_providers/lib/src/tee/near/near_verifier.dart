import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../../common/exchange_tap.dart';
import '../../common/http_errors.dart';
import '../../common/http_settings.dart';
import '../../common/http_transport.dart';
import '../../common/redactor.dart';
import '../attestation_crypto.dart';
import '../attestation_pin_store.dart';
import '../attestation_policy.dart';
import '../attestation_stages.dart';
import '../attestation_types.dart';
import '../codec.dart';
import '../gateway_documents.dart';
import '../session_channel.dart';
import '../tls_pin_gate.dart';
import 'near_e2ee.dart';

/// [AttestationVerifier] for the NEAR AI Cloud (ADR 0019). One verifier
/// attests one [model]: `GET /attestation/report?model=…&provider=near
/// &signing_algo=ed25519&nonce=…&include_tls_fingerprint=true` returns the
/// gateway's own TDX quote and one quote per model instance (candidate).
///
/// Per quote (the same dcap-qvl/`AttestationChecks` as Phala): signature
/// chain and TCB, `report_data = sha256(key ‖ tls_spki) ‖ nonce`, RTMR3
/// replay of the event log, `compose-hash` against `app_compose`, no debug
/// TD. The **model** quote binds the E2EE key (its Ed25519 signing key) and
/// decides; the **gateway** quote binds the TLS key of `cloud-api.near.ai`
/// (the pin of WP61) and is its own stage: an old gateway TCB is a hint
/// there, not a block, because the gateway only sees ciphertext. All
/// candidates are checked; the first one that passes is used. GPU evidence
/// is checked by the GPU gate (`NrasGpuVerifier`), not here.
///
/// Receipts: `GET /signature/{chat_id}` is signed by the model's key over
/// `MODEL:sha256(request wire bytes):sha256(response wire bytes)` (measured
/// 2026-10-15 for streaming with `x-no-aliasing`); a gateway-signed receipt
/// is accepted with a hint.
final class NearVerifier implements AttestationVerifier, ReceiptIdSource {
  /// Creates the verifier. [baseUrl] includes the version path
  /// (`https://cloud-api.near.ai/v1`).
  NearVerifier({
    required this.crypto,
    required this.baseUrl,
    required this.model,
    required this.profileId,
    required this.headers,
    http.Client? client,
    this.settings = const HttpSettings(),
    this.policy = const AttestationPolicy(),
    this.pins,
    this.tlsPin,
    this.trustedComposeHashes = const {},
    this.sessionTtl = const Duration(minutes: 30),
    Uint8List Function()? nonceSource,
  }) : _nonce = nonceSource ?? _secureNonce,
       _checks = AttestationChecks(crypto),
       _transport = HttpTransport(
         client: client ?? defaultHttpClient(),
         settings: settings,
         label: 'Attestierung',
         redactor: Redactor(),
       );

  /// Cryptographic primitives.
  final AttestationCrypto crypto;

  /// API root including the version path.
  final Uri baseUrl;

  /// The attested model id.
  final String model;

  /// Provider profile id (key of the pin).
  final String profileId;

  /// Request headers (API key; the report endpoint needs it).
  final Future<Map<String, String>> Function() headers;

  /// Timeouts, clock and log.
  final HttpSettings settings;

  /// Stage results → status.
  final AttestationPolicy policy;

  /// Pin store; `null` = no pinning.
  final AttestationPinStore? pins;

  /// Pin state shared with the enforcing client (WP61).
  final TlsPinGate? tlsPin;

  /// Trusted compose hashes (hex); empty = only logged (NEAR publishes no
  /// official list). A change of the hash is reported through the pin store.
  final Set<String> trustedComposeHashes;

  /// How long an attested session is used (the report has no expiry).
  final Duration sessionTtl;

  final Uint8List Function() _nonce;
  final AttestationChecks _checks;
  final HttpTransport _transport;

  static final _random = Random.secure();

  static Uint8List _secureNonce() =>
      Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));

  Uri _url(String path, Map<String, String> query) => baseUrl.replace(
    pathSegments: [
      ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/'),
    ],
    queryParameters: query,
  );

  Future<Map<String, Object?>> _get(Uri url) async => _transport.getJson(
    url,
    {...await headers(), 'x-no-aliasing': 'true'},
    onHttpError: (status, body, retry) =>
        exceptionForStatus(status, label: 'Attestierung', retryAfter: retry),
  );

  @override
  Future<AttestationResult> attest() async {
    final gate = tlsPin?..expect(null);
    final nonce = _nonce();
    final now = settings.clock.now();
    final Map<String, Object?> doc;
    try {
      doc = await _get(
        _url('attestation/report', {
          'model': model,
          'provider': 'near',
          'signing_algo': 'ed25519',
          'nonce': AttestCodec.hex(nonce),
          'include_tls_fingerprint': 'true',
        }),
      );
    } on MalformedResponseException {
      return _failed(const [
        StageResult.fail(AttestationStage.quote, 'Antwort nicht lesbar'),
      ]);
    } on ProviderException {
      return _failed(const [
        StageResult(
          AttestationStage.quote,
          StageOutcome.unavailable,
          'Attestierung nicht abrufbar',
        ),
      ]);
    }

    final gatewayJson = doc['gateway_attestation'];
    final candidates = doc['model_attestations'];
    if (gatewayJson is! Map<String, Object?> ||
        candidates is! List<Object?> ||
        candidates.isEmpty) {
      return _failed(const [
        StageResult.fail(AttestationStage.quote, 'Bericht unvollständig'),
      ]);
    }
    final gateway = await _evaluate(gatewayJson, 'signing_address', nonce, now);
    _Entry? chosen;
    final all = <_Entry>[];
    for (final c in candidates) {
      if (c is! Map<String, Object?>) continue;
      final e = await _evaluate(c, 'signing_public_key', nonce, now);
      all.add(e);
      if (chosen == null && e.passed && e.model == model) chosen = e;
    }
    final entry = chosen ?? (all.isEmpty ? null : all.first);
    if (entry == null) {
      return _failed(const [
        StageResult.fail(AttestationStage.quote, 'Kein Modell im Bericht'),
      ]);
    }
    final stages = <StageResult>[
      ...entry.stages,
      if (entry.model != model)
        const StageResult.fail(
          AttestationStage.quote,
          'Bericht gilt für ein anderes Modell',
        ),
      _provenance(entry),
      _tls(gateway, gate),
      _gatewayStage(gateway),
      _e2eeKey(entry),
    ];
    if (all.length > 1) {
      stages.add(
        StageResult(
          AttestationStage.provenance,
          StageOutcome.info,
          '${all.length} Modellinstanzen im Bericht, '
          '${all.where((e) => e.passed).length} geprüft',
        ),
      );
    }
    final status = policy.sessionStatus(stages);
    if (status != AttestationStatus.green || chosen == null) {
      return _failed(stages);
    }
    gate?.expect(gateway.tlsSpkiHex);
    final session = _session(chosen, gateway, now);
    return AttestationResult(
      status: status,
      stages: stages,
      session: session,
      notes: policy.notes(stages),
      pinChange: await _pin(session),
    );
  }

  AttestationResult _failed(List<StageResult> stages) =>
      AttestationResult(status: policy.sessionStatus(stages), stages: stages);

  AttestedSession _session(_Entry model, _Entry gateway, DateTime now) =>
      AttestedSession(
        keysetDigest: AttestCodec.hex(crypto.sha256(model.key!)),
        notAfter: now.add(sessionTtl),
        receiptKeys: {'model': model.key!, 'gateway': gateway.key!},
        repoCommit: null,
        composeHash: model.composeHash ?? '',
        attestedAt: now,
        workloadId: this.model,
        e2eeKey: NearE2eeProtocol.keyOf(AttestCodec.hex(model.key!)),
      );

  Future<PinChange> _pin(AttestedSession s) async {
    final store = pins;
    if (store == null) return PinChange.none;
    final pin = AttestationPin(
      keysetDigest: s.keysetDigest,
      composeHash: s.composeHash,
      repoCommit: s.repoCommit,
      pinnedAt: s.attestedAt,
    );
    final old = await store.load(profileId);
    if (old == null) {
      await store.save(profileId, pin);
      return PinChange.first;
    }
    if (!old.changedBy(pin)) return PinChange.none;
    await store.save(profileId, pin);
    return PinChange.changed;
  }

  // --- Checks of one quote ------------------------------------------------

  Future<_Entry> _evaluate(
    Map<String, Object?> json,
    String keyField,
    Uint8List nonce,
    DateTime now,
  ) async {
    final e = _Entry();
    e.model = json['model_name'] as String?;
    final Uint8List quote;
    final List<TdxEvent> events;
    final String appCompose;
    try {
      e.key = AttestCodec.unhex(json[keyField]! as String);
      e.tlsSpki = AttestCodec.unhex(json['tls_cert_fingerprint']! as String);
      quote = AttestCodec.unhex(json['intel_quote']! as String);
      events = TdxEvent.parseLog(json['event_log']);
      final info = json['info']! as Map<String, Object?>;
      appCompose =
          (info['tcb_info']! as Map<String, Object?>)['app_compose']! as String;
      if (e.key!.length != 32 || e.tlsSpki!.length != 32) {
        throw const FormatException('Schlüssellänge');
      }
      if ((json['request_nonce'] as String?)?.toLowerCase() !=
          AttestCodec.hex(nonce)) {
        throw const FormatException('Nonce');
      }
    } on Object {
      e.stages.add(
        const StageResult.fail(AttestationStage.quote, 'Eintrag unlesbar'),
      );
      return e;
    }
    e.composeHash = AttestCodec.hex(
      crypto.sha256(utf8.encode(appCompose).toU8),
    );
    QuoteVerdict? verdict;
    try {
      final collateral = await crypto.collateralFor(quote);
      verdict = await crypto.verifyQuote(quote, collateral, now);
      e.stages.add(const StageResult.pass(AttestationStage.quote));
    } on QuoteVerificationException catch (x) {
      e.stages.add(StageResult.fail(AttestationStage.quote, x.reason));
    } on CollateralUnavailableException catch (x) {
      e.stages.add(
        StageResult(AttestationStage.quote, StageOutcome.unavailable, x.reason),
      );
    }
    if (verdict == null) return e;
    e.tcb = _checks.tcb(verdict);
    e.stages
      ..add(e.tcb!)
      ..add(_debugBit(quote))
      ..add(_binding(e, verdict, nonce))
      ..add(_checks.eventLogOf(events, verdict))
      ..add(_checks.composeHashOf(appCompose, events));
    return e;
  }

  /// TD attributes bit 0 (DEBUG) of the verified quote must be clear.
  StageResult _debugBit(Uint8List quote) {
    const offset = 48 + 120; // header + td_attributes in the TD report
    if (quote.length < offset + 8) {
      return const StageResult.fail(AttestationStage.quote, 'Quote zu kurz');
    }
    return quote[offset] & 1 == 0
        ? const StageResult.pass(AttestationStage.quote, 'kein Debug-TD')
        : const StageResult.fail(
            AttestationStage.quote,
            'Debug-TD, keine Vertraulichkeit',
          );
  }

  /// `report_data = sha256(key ‖ tls_spki) ‖ nonce`.
  StageResult _binding(_Entry e, QuoteVerdict verdict, Uint8List nonce) {
    final expected = [
      ...crypto.sha256(Uint8List.fromList([...e.key!, ...e.tlsSpki!])),
      ...nonce,
    ];
    return AttestCodec.hex(verdict.reportData) == AttestCodec.hex(expected)
        ? const StageResult.pass(AttestationStage.nonceBinding)
        : const StageResult.fail(
            AttestationStage.nonceBinding,
            'report_data bindet Schlüssel, TLS-Zertifikat und Nonce nicht',
          );
  }

  StageResult _provenance(_Entry e) {
    final hash = e.composeHash;
    if (hash == null) {
      return const StageResult(
        AttestationStage.provenance,
        StageOutcome.info,
        'kein Compose-Hash',
      );
    }
    if (trustedComposeHashes.isEmpty) {
      return StageResult(
        AttestationStage.provenance,
        StageOutcome.info,
        'Compose-Hash ${hash.substring(0, 12)} (keine Liste hinterlegt)',
      );
    }
    return trustedComposeHashes.contains(hash)
        ? StageResult.pass(AttestationStage.provenance, hash.substring(0, 12))
        : StageResult.fail(
            AttestationStage.provenance,
            'Compose-Hash ${hash.substring(0, 12)} nicht vertrauenswürdig',
          );
  }

  StageResult _tls(_Entry gateway, TlsPinGate? gate) {
    const s = AttestationStage.tlsSpki;
    final expected = gateway.tlsSpkiHex;
    if (expected == null) {
      return const StageResult.fail(
        s,
        'Attestierung nennt keinen TLS-Schlüssel',
      );
    }
    if (gate == null) {
      return const StageResult(
        s,
        StageOutcome.info,
        'Zertifikat der Verbindung nicht geprüft',
      );
    }
    final seen = gate.observed;
    if (seen == null) {
      return const StageResult.fail(
        s,
        'Zertifikat der Verbindung nicht messbar',
      );
    }
    return seen == expected
        ? const StageResult.pass(s, 'Verbindung geprüft')
        : const StageResult.fail(
            s,
            'SPKI der Verbindung weicht vom Gateway-Bericht ab',
          );
  }

  /// The gateway quote as one stage: failures fail, an old TCB is a hint.
  StageResult _gatewayStage(_Entry g) {
    const s = AttestationStage.gateway;
    for (final r in g.stages) {
      if (r.outcome == StageOutcome.unavailable) {
        return StageResult(s, StageOutcome.unavailable, r.detail);
      }
      if (r.outcome == StageOutcome.fail && r.stage != AttestationStage.tcb) {
        return StageResult.fail(s, 'Gateway: ${r.detail ?? r.stage.id}');
      }
    }
    final tcb = g.tcb;
    if (tcb != null && tcb.outcome != StageOutcome.pass) {
      return StageResult(
        s,
        StageOutcome.warn,
        'Gateway-Plattform nicht aktuell (${tcb.detail}); '
        'das Gateway sieht nur verschlüsselte Inhalte',
      );
    }
    return const StageResult.pass(s);
  }

  StageResult _e2eeKey(_Entry e) {
    const s = AttestationStage.e2eeKey;
    final key = e.key;
    if (key == null || NearE2eeProtocol.keyOf(AttestCodec.hex(key)) == null) {
      return const StageResult.fail(
        s,
        'Kein Verschlüsselungsschlüssel im Bericht',
      );
    }
    return const StageResult.pass(s, 'ed25519');
  }

  // --- Receipt ------------------------------------------------------------

  @override
  String? receiptIdOf(ExchangeRecord record) {
    final text = utf8.decode(record.responseBytes, allowMalformed: true);
    for (final line in const LineSplitter().convert(text)) {
      if (!line.startsWith('data: {')) continue;
      try {
        final id =
            (jsonDecode(line.substring(6)) as Map<String, Object?>)['id'];
        if (id is String && id.isNotEmpty) return id;
      } on Object {
        return null;
      }
    }
    // Non-streaming answer: one JSON document.
    try {
      final id = (jsonDecode(text) as Map<String, Object?>)['id'];
      return id is String && id.isNotEmpty ? id : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<ReceiptResult> verifyReceipt(
    ReceiptRef ref,
    Uint8List requestBytes,
    Uint8List responseBytes,
  ) async {
    ReceiptResult failed(List<StageResult> stages) => ReceiptResult(
      stages: stages,
      status: policy.receiptStatus(stages, attempt: 1),
      receiptId: ref.id,
    );
    final Map<String, Object?> doc;
    try {
      doc = await _get(
        _url('signature/${ref.id}', {
          'model': model,
          'signing_algo': 'ed25519',
        }),
      );
    } on MalformedResponseException {
      return failed(const [
        StageResult.fail(AttestationStage.receiptFetch, 'Quittung unlesbar'),
      ]);
    } on ProviderException {
      return failed(const [
        StageResult(
          AttestationStage.receiptFetch,
          StageOutcome.unavailable,
          'Quittung nicht abrufbar',
        ),
      ]);
    }
    final text = doc['text'];
    final signature = doc['signature'];
    final signer = doc['signing_address'];
    final kind = doc['signature_kind'];
    if (text is! String || signature is! String || signer is! String) {
      return failed(const [
        StageResult.fail(
          AttestationStage.receiptFetch,
          'Quittung unvollständig',
        ),
      ]);
    }
    final stages = <StageResult>[
      const StageResult.pass(AttestationStage.receiptFetch),
    ];
    final Uint8List signerKey;
    final Uint8List sig;
    try {
      signerKey = AttestCodec.unhex(signer);
      sig = AttestCodec.unhex(signature);
    } on FormatException {
      return failed([
        ...stages,
        const StageResult.fail(
          AttestationStage.receiptSignature,
          'Hex ungültig',
        ),
      ]);
    }
    stages.add(
      crypto.verifyEd25519(
            signerKey,
            Uint8List.fromList(utf8.encode(text)),
            sig,
          )
          ? const StageResult.pass(AttestationStage.receiptSignature)
          : const StageResult.fail(
              AttestationStage.receiptSignature,
              'Signatur ungültig',
            ),
    );
    final gatewaySigned = kind == 'gateway';
    final expectedKey =
        ref.session.receiptKeys[gatewaySigned ? 'gateway' : 'model'];
    final keyMatches =
        expectedKey != null &&
        AttestCodec.hex(expectedKey) == AttestCodec.hex(signerKey);
    final parts = text.split(':');
    final hashes = parts.length >= 2
        ? parts.sublist(parts.length - 2)
        : <String>[];
    final modelId = parts.length > 2
        ? parts.sublist(0, parts.length - 2).join(':')
        : null;
    final modelOk = gatewaySigned || modelId == ref.session.workloadId;
    stages.add(
      !keyMatches
          ? const StageResult.fail(
              AttestationStage.receiptBinding,
              'Signaturschlüssel gehört nicht zur geprüften Attestierung',
            )
          : !modelOk
          ? const StageResult.fail(
              AttestationStage.receiptBinding,
              'Quittung gilt für ein anderes Modell',
            )
          : gatewaySigned
          ? const StageResult(
              AttestationStage.receiptBinding,
              StageOutcome.warn,
              'Quittung vom Gateway signiert, nicht vom Modell',
            )
          : const StageResult.pass(AttestationStage.receiptBinding),
    );
    StageResult hashStage(AttestationStage stage, int index, Uint8List bytes) {
      final actual = AttestCodec.hex(crypto.sha256(bytes));
      return hashes.length == 2 && hashes[index] == actual
          ? StageResult.pass(stage)
          : StageResult.fail(
              stage,
              'Hash passt nicht zu den übertragenen Bytes',
            );
    }

    stages
      ..add(hashStage(AttestationStage.requestHash, 0, requestBytes))
      ..add(hashStage(AttestationStage.responseHash, 1, responseBytes));
    return ReceiptResult(
      stages: stages,
      status: policy.receiptStatus(stages, attempt: 1),
      receiptId: ref.id,
    );
  }
}

extension on List<int> {
  Uint8List get toU8 => Uint8List.fromList(this);
}

/// Result of checking one quote entry of the report.
final class _Entry {
  String? model;
  Uint8List? key;
  Uint8List? tlsSpki;
  String? composeHash;
  StageResult? tcb;
  final List<StageResult> stages = [];

  bool get passed =>
      stages.isNotEmpty &&
      stages.every(
        (s) =>
            s.outcome != StageOutcome.fail &&
            s.outcome != StageOutcome.unavailable,
      );

  String? get tlsSpkiHex => tlsSpki == null ? null : AttestCodec.hex(tlsSpki!);
}
