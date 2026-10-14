import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'codec.dart';

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

/// Result of [GpuAttestationVerifier.verify].
final class GpuAttestationResult {
  /// Creates a result.
  const GpuAttestationResult(this.verdict, [this.detail]);

  /// Outcome.
  final GpuVerdict verdict;

  /// Secret-free reason.
  final String? detail;

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
/// `eat_nonce` is our nonce. The JWT signature is **not** verified (NVIDIA
/// JWKS), see ADR 0014.
final class NrasGpuVerifier implements GpuAttestationVerifier {
  /// Creates the verifier. [baseUrl] includes the version path.
  NrasGpuVerifier({
    required this.baseUrl,
    required this._client,
    this.nrasUrl = 'https://nras.attestation.nvidia.com/v3/attest/gpu',
    this.timeout = const Duration(seconds: 10),
    Uint8List Function()? nonceSource,
  }) : _nonce = nonceSource ?? _secureNonce;

  /// Gateway API root including `/v1`.
  final Uri baseUrl;

  /// NRAS endpoint.
  final String nrasUrl;

  /// Timeout for each of the two requests.
  final Duration timeout;

  final http.Client _client;
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
        return const GpuAttestationResult(
          GpuVerdict.unreachable,
          'NRAS nicht verfügbar',
        );
      }
      if (nras.statusCode != 200) {
        return const GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS lehnt die Evidenz ab',
        );
      }
      return _judge(nras.bodyBytes, nonce);
    } on TimeoutException {
      return const GpuAttestationResult(
        GpuVerdict.timeout,
        'NRAS Zeitüberschreitung',
      );
    } on Object {
      return const GpuAttestationResult(
        GpuVerdict.unreachable,
        'NRAS nicht erreichbar',
      );
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
    final nonce = AttestCodec.hex(_nonce());
    GpuAttestationResult? fail(GpuVerdict v, String detail) =>
        GpuAttestationResult(v, detail);
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
          result: fail(GpuVerdict.unreachable, 'GPU-Evidenz nicht abrufbar'),
          payload: null,
          nonce: nonce,
        );
      }
      final payload = _payload(report.bodyBytes);
      if (payload == null) {
        return (
          result: fail(GpuVerdict.failed, 'GPU-Evidenz fehlt'),
          payload: null,
          nonce: nonce,
        );
      }
      if ((payload['nonce'] as String?)?.toLowerCase() != nonce) {
        return (
          result: fail(GpuVerdict.failed, 'GPU-Evidenz bindet die Nonce nicht'),
          payload: null,
          nonce: nonce,
        );
      }
      return (result: null, payload: payload, nonce: nonce);
    } on TimeoutException {
      return (
        result: fail(GpuVerdict.timeout, 'NRAS Zeitüberschreitung'),
        payload: null,
        nonce: nonce,
      );
    } on Object {
      return (
        result: fail(GpuVerdict.unreachable, 'NRAS nicht erreichbar'),
        payload: null,
        nonce: nonce,
      );
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

  static GpuAttestationResult _judge(List<int> body, String nonce) {
    try {
      final decoded = jsonDecode(utf8.decode(body)) as List<Object?>;
      final overall = (decoded.first as List<Object?>)[1]! as String;
      final claims = jsonDecode(
        utf8.decode(
          base64Url.decode(base64Url.normalize(overall.split('.')[1])),
        ),
      ) as Map<String, Object?>;
      if (claims['x-nvidia-overall-att-result'] != true) {
        return const GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS: Gesamtergebnis negativ',
        );
      }
      if ((claims['eat_nonce'] as String?)?.toLowerCase() != nonce) {
        return const GpuAttestationResult(
          GpuVerdict.failed,
          'NRAS: Nonce stimmt nicht',
        );
      }
      return const GpuAttestationResult(GpuVerdict.verified);
    } on Object {
      return const GpuAttestationResult(
        GpuVerdict.failed,
        'NRAS-Antwort unlesbar',
      );
    }
  }
}
