import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

/// Parsed JSON fixture of the 2026-10-14 probe (`test/fixtures/tee/`).
Map<String, Object?> teeJson(String name) =>
    jsonDecode(File('test/fixtures/tee/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// Deep copy of [json] so tests can manipulate it.
Map<String, Object?> copyJson(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

/// The nonce of the probe (32 × 0xab).
final probeNonce = Uint8List.fromList(List.filled(32, 0xab));

/// Check time of the offline probe (collateral valid).
final probeNow = DateTime.fromMillisecondsSinceEpoch(
  1791934700 * 1000,
  isUtc: true,
);

/// A scripted answer for [TeeServer].
typedef TeeHandler = FutureOr<http.Response> Function(http.Request request);

/// Mock gateway that routes by URL path and records the requests.
final class TeeServer {
  /// Creates a server; [routes] maps a path suffix (e.g. `aci/attestation`)
  /// to its handler.
  TeeServer(this.routes);

  /// Routes by path suffix.
  final Map<String, TeeHandler> routes;

  /// Requests received.
  final List<http.Request> requests = [];

  /// The client to inject.
  late final http.Client client = MockClient((request) async {
    requests.add(request);
    for (final e in routes.entries) {
      if (request.url.path.contains(e.key)) return e.value(request);
    }
    return http.Response('{"error":"nicht gefunden"}', 404);
  });

  /// Number of requests whose path contains [part].
  int count(String part) =>
      requests.where((r) => r.url.path.contains(part)).length;
}

/// JSON handler returning [body].
TeeHandler jsonBody(Object? body, {int status = 200}) =>
    (_) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

/// A [PhalaVerifier] against [server] with the probe's nonce.
PhalaVerifier probeVerifier(
  TeeServer server,
  AttestationCrypto crypto, {
  DateTime? now,
  Uint8List? nonce,
  Set<String> trustedCommits = const {},
  AttestationPinStore? pins,
  bool expectUpstreamEnforced = true,
}) => PhalaVerifier(
  crypto: crypto,
  baseUrl: Uri.parse('https://gateway.test/v1'),
  profileId: 'phala',
  client: server.client,
  settings: HttpSettings(clock: FixedClock(now ?? probeNow)),
  nonceSource: () => nonce ?? probeNonce,
  trustedCommits: trustedCommits,
  pins: pins,
  expectUpstreamEnforced: expectUpstreamEnforced,
);

/// Server answering the attestation with [attestation].
TeeServer attestationServer([Map<String, Object?>? attestation]) => TeeServer({
  'aci/attestation': jsonBody(attestation ?? teeJson('gateway_attestation')),
});

/// The stages of [stages] with [outcome].
List<AttestationStage> stagesWith(
  Iterable<StageResult> stages,
  StageOutcome outcome,
) => [
  for (final s in stages)
    if (s.outcome == outcome) s.stage,
];

/// `sha256:<hex>` of [bytes] with the fake's real hash function.
String sha256Of(Uint8List bytes) =>
    'sha256:${FakeAttestationCrypto().sha256(bytes).map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';

/// The probe receipt with hashes that match [request] and [response] and
/// `required: true`. The signature is no longer valid: use a
/// `FakeAttestationCrypto(ed25519Result: true)`.
Map<String, Object?> syntheticReceipt(
  Uint8List request,
  Uint8List response, [
  void Function(Map<String, Object?>)? edit,
]) {
  final r = copyJson(teeJson('receipt'));
  for (final e in (r['event_log']! as List).cast<Map<String, Object?>>()) {
    switch (e['type']) {
      case 'request.received' || 'middleware.forwarded' || 'request.forwarded':
        e['body_hash'] = sha256Of(request);
      case 'response.returned':
        e['body_hash'] = sha256Of(response);
      case 'upstream.verified':
        e['required'] = true;
    }
  }
  edit?.call(r);
  return r;
}
