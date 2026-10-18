import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import 'codec.dart';
import 'nras_jwt.dart';

/// When the GPU evidence is checked at NVIDIA NRAS (M4, decision 4).
enum GpuCheckMode {
  /// Never; no call to NVIDIA.
  off,

  /// Before the request content leaves the device; fail-closed.
  before,

  /// Asynchronously after the answer; a failure warns and makes the next
  /// request check first.
  after,
}

/// Outcome of a GPU check.
enum GpuVerdict {
  /// NRAS confirms the evidence and our nonce.
  verified,

  /// The evidence was rejected or does not bind our nonce.
  failed,

  /// NRAS (or the report) could not be reached.
  unreachable,

  /// NRAS did not answer in time.
  timeout,
}

/// Categories of a failed GPU check ([GpuAttestationResult.category]): they
/// reach the log line (`Wendelin/attest: gpu …`), the audit entry and the
/// warning, so the user sees *why* (WP77).
abstract final class GpuReason {
  /// The gateway delivers no GPU evidence for the model (`evidence_list`
  /// empty or no `nvidia_payload`); NVIDIA cannot check what is not there.
  static const noEvidence = 'no_evidence';

  /// The evidence does not bind our nonce (local or NRAS `eat_nonce`).
  static const nonceMismatch = 'nonce_mismatch';

  /// NRAS says the overall result is negative (claim rejected).
  static const claimRejected = 'claim_rejected';

  /// No answer in time.
  static const timeout = 'timeout';

  /// Network failure.
  static const unreachable = 'unreachable';

  /// The NRAS answer could not be read.
  static const unreadable = 'unreadable';

  /// Unexpected internal error.
  static const internal = 'internal';

  /// The NRAS token is not trustworthy: wrong signature, unknown key, wrong
  /// algorithm or issuer, expired, or the detached GPU tokens do not match
  /// their digests (WP83). Detail category: `nras_signature`.
  static const signature = 'nras_signature';

  /// The NVIDIA JWKS could not be fetched; handled like NRAS unreachable.
  static const jwks = 'jwks_unavailable';
}

/// Result of [GpuAttestationVerifier.verify].
final class GpuAttestationResult {
  /// Creates a result.
  const GpuAttestationResult(
    this.verdict, [
    this.detail,
    this.category,
    this.signatureChecked = false,
  ]);

  /// Outcome.
  final GpuVerdict verdict;

  /// Secret-free reason.
  final String? detail;

  /// Machine-readable reason of a failure, a [GpuReason] value or
  /// `nras_http_<status>` / `report_http_<status>`; `null` when verified.
  final String? category;

  /// Whether the NRAS token's signature was verified against NVIDIA's JWKS
  /// and the claims were read from that verified token (WP83).
  final bool signatureChecked;

  /// Whether the GPU evidence is confirmed.
  bool get ok => verdict == GpuVerdict.verified;
}

/// Checks the GPU attestation of a TEE model (NVIDIA NRAS). Never throws.
abstract interface class GpuAttestationVerifier {
  /// Local part only, **no call to NVIDIA**: fetches the gateway's GPU
  /// evidence with a fresh nonce and checks that it binds that nonce. Runs
  /// in every [GpuCheckMode], also `off`.
  Future<GpuAttestationResult> verifyLocal({required String model});

  /// Checks the GPU evidence of [model] with a fresh nonce.
  Future<GpuAttestationResult> verify({required String model});
}

/// [GpuAttestationVerifier] for the gateway report + NVIDIA NRAS
/// (`POST /v3/attest/gpu`, no key needed).
///
/// Steps: fetch `GET {baseUrl}/attestation/report?model=&nonce=`, check
/// locally that `nvidia_payload.nonce` is our nonce, send the payload to
/// NRAS, read the overall JWT: `x-nvidia-overall-att-result` is `true` and
/// `eat_nonce` is our nonce. The JWT signature (ES384) is verified against
/// NVIDIA's JWKS ([NrasTokenVerifier]) and the claims are read only from the
/// verified token; a wrong signature or an unknown key is red, an
/// unreachable JWKS counts as NRAS unreachable (WP83, ADR 0014).
final class NrasGpuVerifier implements GpuAttestationVerifier {
  /// Creates the verifier. [baseUrl] includes the version path.
  NrasGpuVerifier({
    required this.baseUrl,
    required this._client,
    this.nrasUrl = 'https://nras.attestation.nvidia.com/v3/attest/gpu',
    this.timeout = const Duration(seconds: 10),
    this.evidenceSource,
    Uint8List Function()? nonceSource,
    NrasTokenChecker? tokenChecker,
  }) : _nonce = nonceSource ?? _secureNonce,
       _tokens =
           tokenChecker ?? NrasTokenVerifier(jwks: NrasJwks(client: _client));

  /// Gateway API root including `/v1`.
  final Uri baseUrl;

  /// NRAS endpoint.
  final String nrasUrl;

  /// Timeout for each of the two requests.
  final Duration timeout;

  /// Evidence of an already verified attestation instead of an own report
  /// request (NEAR AI: the `nvidia_payload` of the chosen candidate, same
  /// nonce as the TDX quote; no gateway call, no API key). `null` result =
  /// no evidence.
  final Future<({Map<String, Object?> payload, String nonce})?> Function()?
  evidenceSource;

  final http.Client _client;
  final NrasTokenChecker _tokens;
  final Uint8List Function() _nonce;
  static final _random = Random.secure();

  static Uint8List _secureNonce() =>
      Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)));

  @override
  Future<GpuAttestationResult> verifyLocal({required String model}) async {
    final (:result, payload: _, nonce: _) = await _evidence(model);
    return result ?? const GpuAttestationResult(GpuVerdict.verified);
  }

  @override
  Future<GpuAttestationResult> verify({required String model}) async {
    final (:result, :payload, :nonce) = await _evidence(model);
    if (result != null) return result;
    try {
      final nras = await _client
          .post(
            Uri.parse(nrasUrl),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      if (nras.statusCode >= 500 || nras.statusCode == 429) {
        return GpuAttestationResult(
          GpuVerdict.unreachable,
          'NRAS nicht verfügbar (HTTP ${nras.statusCode})',
          'nras_http_${nras.statusCode}',
        );
      }
      if (nras.statusCode != 200) {
        final code = _nrasCode(nras.bodyBytes);
        return GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS lehnt die Evidenz ab (HTTP ${nras.statusCode}'
              '${code == null ? '' : ', $code'})',
          'nras_http_${nras.statusCode}',
        );
      }
      return await _judge(nras.bodyBytes, nonce);
    } on TimeoutException {
      return const GpuAttestationResult(
        GpuVerdict.timeout,
        'NRAS Zeitüberschreitung',
        GpuReason.timeout,
      );
    } on Object {
      return const GpuAttestationResult(
        GpuVerdict.unreachable,
        'NRAS nicht erreichbar',
        GpuReason.unreachable,
      );
    }
  }

  /// The short error name of an NRAS error body (`message`, e.g.
  /// `INVALID_EVIDENCE`); `null` unless it is a plain upper-case code, so no
  /// free text ends up in the log.
  static String? _nrasCode(List<int> body) {
    try {
      final json = jsonDecode(utf8.decode(body));
      final m = json is Map<String, Object?> ? json['message'] : null;
      return m is String && RegExp(r'^[A-Z][A-Z0-9_]{2,47}$').hasMatch(m)
          ? m
          : null;
    } on Object {
      return null;
    }
  }

  /// Fetches the evidence and checks our nonce in it; [result] is the
  /// failure, or `null` if the evidence binds the nonce.
  Future<
    ({
      GpuAttestationResult? result,
      Map<String, Object?>? payload,
      String nonce,
    })
  >
  _evidence(String model) async {
    final source = evidenceSource;
    if (source != null) {
      try {
        final given = await source();
        if (given == null) {
          return (
            result: const GpuAttestationResult(
              GpuVerdict.failed,
              'Keine GPU-Evidenz im Bericht des Anbieters',
              GpuReason.noEvidence,
            ),
            payload: null,
            nonce: '',
          );
        }
        if (_noEntries(given.payload)) {
          return (
            result: const GpuAttestationResult(
              GpuVerdict.failed,
              _emptyEvidence,
              GpuReason.noEvidence,
            ),
            payload: null,
            nonce: given.nonce,
          );
        }
        if ((given.payload['nonce'] as String?)?.toLowerCase() !=
            given.nonce.toLowerCase()) {
          return (
            result: const GpuAttestationResult(
              GpuVerdict.failed,
              'GPU-Evidenz bindet die Nonce nicht',
              GpuReason.nonceMismatch,
            ),
            payload: null,
            nonce: given.nonce,
          );
        }
        return (
          result: null,
          payload: given.payload,
          nonce: given.nonce.toLowerCase(),
        );
      } on Object {
        return (
          result: const GpuAttestationResult(
            GpuVerdict.failed,
            'GPU-Evidenz unlesbar',
            GpuReason.unreadable,
          ),
          payload: null,
          nonce: '',
        );
      }
    }
    final nonce = AttestCodec.hex(_nonce());
    GpuAttestationResult? fail(GpuVerdict v, String detail, String category) =>
        GpuAttestationResult(v, detail, category);
    try {
      final report = await _client
          .get(
            baseUrl.replace(
              pathSegments: [
                ...baseUrl.pathSegments.where((s) => s.isNotEmpty),
                'attestation',
                'report',
              ],
              queryParameters: {'model': model, 'nonce': nonce},
            ),
          )
          .timeout(timeout);
      if (report.statusCode != 200) {
        return (
          result: fail(
            GpuVerdict.unreachable,
            'GPU-Evidenz nicht abrufbar (HTTP ${report.statusCode})',
            'report_http_${report.statusCode}',
          ),
          payload: null,
          nonce: nonce,
        );
      }
      final payload = _payload(report.bodyBytes);
      if (payload == null) {
        return (
          result: fail(
            GpuVerdict.failed,
            'Keine GPU-Evidenz im Bericht des Anbieters',
            GpuReason.noEvidence,
          ),
          payload: null,
          nonce: nonce,
        );
      }
      if (_noEntries(payload)) {
        return (
          result: fail(GpuVerdict.failed, _emptyEvidence, GpuReason.noEvidence),
          payload: null,
          nonce: nonce,
        );
      }
      if ((payload['nonce'] as String?)?.toLowerCase() != nonce) {
        return (
          result: fail(
            GpuVerdict.failed,
            'GPU-Evidenz bindet die Nonce nicht',
            GpuReason.nonceMismatch,
          ),
          payload: null,
          nonce: nonce,
        );
      }
      return (result: null, payload: payload, nonce: nonce);
    } on TimeoutException {
      return (
        result: fail(
          GpuVerdict.timeout,
          'Zeitüberschreitung beim Abruf der GPU-Evidenz',
          GpuReason.timeout,
        ),
        payload: null,
        nonce: nonce,
      );
    } on Object {
      return (
        result: fail(
          GpuVerdict.unreachable,
          'GPU-Evidenz nicht erreichbar',
          GpuReason.unreachable,
        ),
        payload: null,
        nonce: nonce,
      );
    }
  }

  static const _emptyEvidence =
      'Der Anbieter liefert für dieses Modell keine GPU-Evidenz '
      '(evidence_list leer), NVIDIA kann nichts prüfen';

  /// Whether the payload lists no GPU at all (NRAS would answer 400
  /// `INVALID_EVIDENCE`).
  static bool _noEntries(Map<String, Object?> payload) {
    final list = payload['evidence_list'];
    return list is! List || list.isEmpty;
  }

  /// Decodes an `nvidia_payload` (JSON text or object); `null` if unreadable.
  static Map<String, Object?>? decodePayload(Object? raw) {
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, Object?>? _payload(List<int> body) {
    try {
      final report = jsonDecode(utf8.decode(body));
      final raw = report is Map<String, Object?>
          ? report['nvidia_payload']
          : null;
      final decoded = raw is String ? jsonDecode(raw) : raw;
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  Future<GpuAttestationResult> _judge(List<int> body, String nonce) async {
    final List<Object?> decoded;
    final String overall;
    try {
      decoded = jsonDecode(utf8.decode(body)) as List<Object?>;
      overall = (decoded.first as List<Object?>)[1]! as String;
    } on Object {
      return _unreadable;
    }
    final Map<String, Object?> claims;
    try {
      claims = await _tokens.verify(overall);
    } on NrasJwtException catch (e) {
      return e.unavailable
          ? const GpuAttestationResult(
              GpuVerdict.unreachable,
              'NVIDIA-Schlüssel (JWKS) nicht abrufbar',
              GpuReason.jwks,
            )
          : GpuAttestationResult(
              GpuVerdict.failed,
              'NRAS-Token nicht vertrauenswürdig (${e.reason})',
              GpuReason.signature,
            );
    } on Object {
      return _unreadable;
    }
    try {
      if (claims['x-nvidia-overall-att-result'] != true) {
        return const GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS: Gesamtergebnis negativ (Nachweis abgelehnt)',
          GpuReason.claimRejected,
        );
      }
      if ((claims['eat_nonce'] as String?)?.toLowerCase() != nonce) {
        return const GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS: Nonce stimmt nicht',
          GpuReason.nonceMismatch,
        );
      }
      if (!_detachedMatch(claims, decoded.length > 1 ? decoded[1] : null)) {
        return const GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS: GPU-Tokens passen nicht zum signierten Gesamttoken',
          GpuReason.signature,
        );
      }
      return const GpuAttestationResult(GpuVerdict.verified, null, null, true);
    } on Object {
      return _unreadable;
    }
  }

  static const _unreadable = GpuAttestationResult(
    GpuVerdict.failed,
    'NRAS-Antwort unlesbar',
    GpuReason.unreadable,
  );

  /// Every GPU of the signed `submods` has a detached token whose SHA-256
  /// equals the signed digest (and vice versa); without detached tokens in
  /// the answer there is nothing to bind.
  static bool _detachedMatch(Map<String, Object?> claims, Object? detached) {
    if (detached is! Map<String, Object?>) return true;
    final submods = claims['submods'];
    if (submods is! Map<String, Object?>) return false;
    if (submods.length != detached.length) return false;
    for (final e in submods.entries) {
      final digest = e.value;
      final token = detached[e.key];
      if (digest is! List || token is! String) return false;
      final inner = digest.length > 1 ? digest[1] : null;
      if (inner is! List || inner.length < 2 || inner[0] != 'SHA-256') {
        return false;
      }
      final actual = crypto.sha256.convert(utf8.encode(token)).toString();
      if (actual != inner[1]) return false;
    }
    return true;
  }
}
