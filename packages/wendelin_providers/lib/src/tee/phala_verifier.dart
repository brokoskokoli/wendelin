import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../common/http_errors.dart';
import '../common/http_settings.dart';
import '../common/http_transport.dart';
import '../common/redactor.dart';
import 'attestation_crypto.dart';
import 'attestation_pin_store.dart';
import 'attestation_policy.dart';
import 'attestation_stages.dart';
import 'attestation_types.dart';
import 'codec.dart';
import 'gateway_documents.dart';
import 'receipt_checks.dart';

/// [AttestationVerifier] for the Phala/RedPill gateway (ACI, spec
/// `Dstack-TEE/private-ai-gateway`). [baseUrl] includes the version path,
/// e.g. `https://api.redpill.ai/v1`.
///
/// Every stage runs independently and is reported on its own; one failed
/// stage does not hide the others in the audit log.
final class PhalaVerifier implements AttestationVerifier {
  /// Creates the verifier.
  PhalaVerifier({
    required this.crypto,
    required this.baseUrl,
    required this.profileId,
    http.Client? client,
    this.settings = const HttpSettings(),
    this.trustedCommits = const {},
    this.policy = const AttestationPolicy(),
    this.pins,
    this.headers,
    this.observedSpki,
    this.enforceTlsPin = false,
    this.expectUpstreamEnforced = true,
    Uint8List Function()? nonceSource,
  }) : _nonce = nonceSource ?? _secureNonce,
       _checks = AttestationChecks(crypto),
       _transport = HttpTransport(
         client: client ?? defaultHttpClient(),
         settings: settings,
         label: 'Attestierung',
         redactor: Redactor(),
       );

  /// Cryptographic primitives (Rust in the app, fake in tests).
  final AttestationCrypto crypto;

  /// API root including the version path.
  final Uri baseUrl;

  /// Provider profile id (key of the pin).
  final String profileId;

  /// Timeouts, clock and log.
  final HttpSettings settings;

  /// Trusted `repo_commit`s; empty = only logged.
  final Set<String> trustedCommits;

  /// Stage results → status.
  final AttestationPolicy policy;

  /// Pin store; `null` = no pinning.
  final AttestationPinStore? pins;

  /// Optional request headers (the endpoints work without a key).
  final Future<Map<String, String>> Function()? headers;

  /// Hex SPKI hash of the certificate seen on the TLS connection, if the
  /// platform provides it (see ADR 0014, open finding).
  final Future<String?> Function()? observedSpki;

  /// Make a mismatch of [observedSpki] a failure (default: logged only).
  final bool enforceTlsPin;

  /// Require `upstream.verified.required == true` (the request carried
  /// `provider.aci_verified`).
  final bool expectUpstreamEnforced;

  final Uint8List Function() _nonce;
  final AttestationChecks _checks;
  final HttpTransport _transport;

  static final _random = Random.secure();

  static Uint8List _secureNonce() =>
      Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));

  Uri _url(String path, [Map<String, String>? query]) => baseUrl.replace(
    pathSegments: [
      ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
      ...path.split('/'),
    ],
    queryParameters: query,
  );

  Future<Map<String, Object?>> _get(Uri url) async => _transport.getJson(
    url,
    await headers?.call() ?? const {},
    onHttpError: (status, body, retry) =>
        exceptionForStatus(status, label: 'Attestierung', retryAfter: retry),
  );

  @override
  Future<AttestationResult> attest() async {
    final nonce = _nonce();
    final now = settings.clock.now();
    final GatewayAttestation doc;
    try {
      final json = await _get(
        _url('aci/attestation', {'nonce': AttestCodec.hex(nonce)}),
      );
      doc = GatewayAttestation.parse(json);
    } on AttestationFormatException catch (e) {
      return _attestFailed([StageResult.fail(e.stage, e.message)]);
    } on MalformedResponseException {
      return _attestFailed(const [
        StageResult.fail(AttestationStage.quote, 'Antwort nicht lesbar'),
      ]);
    } on ProviderException {
      return _attestFailed(const [
        StageResult(
          AttestationStage.quote,
          StageOutcome.unavailable,
          'Attestierung nicht abrufbar',
        ),
      ]);
    }

    final stages = <StageResult>[];
    QuoteVerdict? verdict;
    try {
      final collateral = await crypto.collateralFor(doc.quote);
      verdict = await crypto.verifyQuote(doc.quote, collateral, now);
      stages.add(const StageResult.pass(AttestationStage.quote));
    } on QuoteVerificationException catch (e) {
      stages.add(StageResult.fail(AttestationStage.quote, e.reason));
    } on CollateralUnavailableException catch (e) {
      stages.add(
        StageResult(AttestationStage.quote, StageOutcome.unavailable, e.reason),
      );
    }
    if (verdict != null) {
      stages
        ..add(_checks.tcb(verdict))
        ..add(_checks.nonceBinding(doc, verdict, nonce));
    }
    stages
      ..add(_checks.keysetDigest(doc))
      ..add(_checks.keysetEndorsement(doc))
      ..add(_checks.freshness(doc, now));
    if (verdict != null) stages.add(_checks.eventLog(doc, verdict));
    stages
      ..add(_checks.composeHash(doc))
      ..add(_checks.provenance(doc, trustedCommits))
      ..add(
        _checks.tlsSpki(
          doc,
          observedSpki: await observedSpki?.call(),
          enforce: enforceTlsPin,
        ),
      );

    final status = policy.sessionStatus(stages);
    if (status != AttestationStatus.green) return _attestFailed(stages);
    final session = _session(doc, now);
    return AttestationResult(
      status: status,
      stages: stages,
      session: session,
      notes: policy.notes(stages),
      pinChange: await _pin(session),
    );
  }

  AttestationResult _attestFailed(List<StageResult> stages) =>
      AttestationResult(status: policy.sessionStatus(stages), stages: stages);

  AttestedSession _session(GatewayAttestation doc, DateTime now) =>
      AttestedSession(
        keysetDigest: doc.keysetDigest,
        notAfter: DateTime.fromMillisecondsSinceEpoch(
          doc.keyset.notAfterEpoch * 1000,
          isUtc: true,
        ),
        receiptKeys: {
          for (final k in doc.keyset.receiptSigningKeys)
            if (k.algo == 'ed25519') k.keyId: AttestCodec.unhex(k.publicKey),
        },
        repoCommit: doc.repoCommit,
        composeHash: AttestCodec.hex(crypto.sha256(utf8Bytes(doc.appCompose))),
        attestedAt: now,
        workloadId: doc.workloadId,
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

  @override
  Future<ReceiptResult> verifyReceipt(
    ReceiptRef ref,
    Uint8List requestBytes,
    Uint8List responseBytes,
  ) async {
    final GatewayReceipt receipt;
    try {
      receipt = GatewayReceipt.parse(
        await _get(_url('aci/receipts/${ref.id}')),
      );
    } on AttestationFormatException catch (e) {
      return _receiptFailed([StageResult.fail(e.stage, e.message)], ref);
    } on MalformedResponseException {
      return _receiptFailed(const [
        StageResult.fail(AttestationStage.receiptFetch, 'Quittung unlesbar'),
      ], ref);
    } on ProviderException {
      return _receiptFailed(const [
        StageResult(
          AttestationStage.receiptFetch,
          StageOutcome.unavailable,
          'Quittung nicht abrufbar',
        ),
      ], ref);
    }
    final checks = ReceiptChecks(
      crypto,
      expectUpstreamEnforced: expectUpstreamEnforced,
    );
    final run = checks.run(receipt, ref.session, requestBytes, responseBytes);
    final stages = [
      const StageResult.pass(AttestationStage.receiptFetch),
      ...run,
      if (run.last.outcome == StageOutcome.pass)
        await _upstreamTcb(receipt.event('upstream.verified')),
    ];
    return ReceiptResult(
      stages: stages,
      status: policy.receiptStatus(stages, attempt: 1),
      pinChanged: receipt.keysetDigest != ref.session.keysetDigest,
      receiptId: ref.id,
    );
  }

  /// Loads the upstream session named in `upstream.verified` and judges its
  /// TCB; a session that cannot be loaded is `unavailable` (retried like
  /// the receipt).
  Future<StageResult> _upstreamTcb(ReceiptEvent? event) async {
    const s = AttestationStage.upstreamTcb;
    final id = event?.raw['session_id'];
    if (id is! String || id.isEmpty) {
      return const StageResult.fail(s, 'session_id fehlt');
    }
    try {
      final session = GatewaySession.parse(
        await _get(_url('aci/sessions/$id')),
      );
      final actual = AttestCodec.hex(
        crypto.sha256(AttestCodec.jcsBytes(session.raw)),
      );
      if (actual != id.toLowerCase()) {
        return const StageResult.fail(
          s,
          'Upstream-Session passt nicht zur signierten session_id',
          code: StageResult.upstreamSessionMismatch,
        );
      }
      return upstreamTcbStage(session);
    } on AttestationFormatException catch (e) {
      return StageResult.fail(s, e.message);
    } on MalformedResponseException {
      return const StageResult.fail(s, 'Upstream-Session unlesbar');
    } on ProviderException {
      return const StageResult(
        s,
        StageOutcome.unavailable,
        'Upstream-Session nicht abrufbar',
      );
    }
  }

  ReceiptResult _receiptFailed(List<StageResult> stages, ReceiptRef ref) =>
      ReceiptResult(
        stages: stages,
        status: policy.receiptStatus(stages, attempt: 1),
        receiptId: ref.id,
      );
}

/// UTF-8 bytes of [s].
Uint8List utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));
