import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'tee_fixtures.g.dart';

/// Nonce of the offline probe (32 × 0xab); the attestation fixture binds it.
final probeNonce = Uint8List.fromList(List.filled(32, 0xab));

/// Check time of the probe (collateral valid).
final probeNow = DateTime.fromMillisecondsSinceEpoch(
  1791934700 * 1000,
  isUtc: true,
);

Map<String, Object?> _copy(Object? json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

String _sha(Uint8List bytes) =>
    'sha256:${FakeAttestationCrypto().sha256(bytes).map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';

String _jcs(Object? v) => switch (v) {
  Map() =>
    '{${(v.keys.cast<String>().toList()..sort()).map((k) => '${jsonEncode(k)}:${_jcs(v[k])}').join(',')}}',
  List() => '[${v.map(_jcs).join(',')}]',
  _ => jsonEncode(v),
};

/// The probe's upstream session with an up-to-date TCB.
Map<String, Object?> upToDateSession() {
  final s = _copy(jsonDecode(session));
  final claims = s['claims']! as Map<String, Object?>;
  (claims['extra']! as Map<String, Object?>)['tcb_status'] = 'UpToDate';
  claims['tcb_up_to_date'] = {
    'status': 'asserted',
    'source': 'hardware_proven',
  };
  return s;
}

const _sse =
    'data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{"role":"assistant","content":"Ruhig: 0,4 m Welle."},'
    '"finish_reason":null}]}\n\n'
    'data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

/// Stand-in certificate of the recorded gateway. The recording lists the pin
/// [fixtureGatewayPin] for `api.redpill.ai`; no real certificate with that
/// key exists any more, so the device test's crypto maps exactly these bytes
/// to the pin (see `_ReceiptSignatureSubstitute`). Any other certificate is
/// hashed by the real Rust module.
final Uint8List fixtureGatewayCertificate = Uint8List.fromList(
  utf8.encode('wendelin-fixture-gateway-certificate'),
);

/// `tls_public_keys` entry of `api.redpill.ai` in the recorded attestation.
const fixtureGatewayPin =
    'c68585e7dc00a55d3082a9c860cb916e1788c5daec51505e413d27ab94f7d4c7';

/// Stand-in for `PinnedHttpClient` in the device test: there is no TLS
/// connection to the recorded gateway, so each request is judged against the
/// pin with the fixture certificate, exactly like the real client does per
/// connection (enforcing: refuse before [_inner] sees the request;
/// measuring: record the certificate).
final class FixturePinnedClient extends http.BaseClient {
  /// Creates the client.
  FixturePinnedClient(this._inner, this.gate, {required this.enforce});

  final http.Client _inner;

  /// Pin state shared with the verifier.
  final TlsPinGate gate;

  /// Whether a mismatch stops the request.
  final bool enforce;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (enforce) {
      gate.enforce(fixtureGatewayCertificate);
    } else {
      gate.resetObserved();
      gate.observe(fixtureGatewayCertificate);
    }
    return _inner.send(request);
  }
}

/// `e2ee_public_keys` entry (x25519) of the recorded attestation. Nobody has
/// its secret, so the device test's crypto encrypts to [FixtureGateway.e2ee]
/// instead (see `_ReceiptSignatureSubstitute`); the request still names this
/// key in `X-Model-Pub-Key`.
const fixtureServiceKeyHex =
    '408e82d159832cfae15007781bcade0badee7d50e9f76d50eaa1777464006537';

/// Fixture transport of the gateway: attestation, session, receipts (built
/// from the bytes of the exchange, like the real gateway would sign them),
/// chat and model list. [tamper] changes the receipt before it is served
/// (a manipulated receipt).
final class FixtureGateway {
  /// Creates the gateway.
  FixtureGateway();

  /// Changes the next receipts, if set.
  void Function(Map<String, Object?> receipt)? tamper;

  /// Chat requests received.
  int chats = 0;

  /// Delay before a receipt is served (WP81: the answer must not wait).
  Duration receiptDelay = Duration.zero;

  /// The service side of the end-to-end encryption (WP62): decrypts the
  /// requests and encrypts the answers with the real protocol.
  final FakeE2eeService e2ee = FakeE2eeService(
    now: () => probeNow,
    alsoAcceptModelKeys: {fixtureServiceKeyHex},
  );

  /// Answers without encryption (a gateway that ignores E2EE).
  bool plainAnswer = false;

  /// The decrypted body of the last chat request.
  Map<String, Object?>? lastPlainBody;

  Uint8List _request = Uint8List(0);
  Uint8List _response = Uint8List(0);

  /// The pinned client (see [FixturePinnedClient]).
  http.Client pinned(TlsPinGate gate, {required bool enforce}) =>
      FixturePinnedClient(client, gate, enforce: enforce);

  /// The HTTP client.
  late final http.Client client = MockClient((request) async {
    final path = request.url.path;
    http.Response json(Object? body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );
    if (path.endsWith('attestation/report')) {
      // GPU evidence of the model: only the nonce binding is checked locally
      // (mode „Aus“), so the recorded payload is replaced by one with the
      // verifier's own nonce.
      return json({
        'nvidia_payload': {
          'nonce': request.url.queryParameters['nonce'],
          'evidence_list': <Object?>[],
        },
      });
    }
    if (path.endsWith('aci/attestation')) {
      return json(jsonDecode(gatewayAttestation));
    }
    if (path.contains('aci/sessions/')) return json(upToDateSession());
    if (path.contains('aci/receipts/')) {
      if (receiptDelay > Duration.zero) {
        await Future<void>.delayed(receiptDelay);
      }
      final r = _copy(jsonDecode(receipt));
      final id = _sha(Uint8List.fromList(utf8.encode(_jcs(upToDateSession()))))
          .substring('sha256:'.length);
      for (final e in (r['event_log']! as List).cast<Map<String, Object?>>()) {
        switch (e['type']) {
          case 'request.received' ||
              'middleware.forwarded' ||
              'request.forwarded':
            e['body_hash'] = _sha(_request);
          case 'response.returned':
            e['body_hash'] = _sha(_response);
          case 'upstream.verified':
            e['required'] = true;
            e['session_id'] = id;
        }
      }
      tamper?.call(r);
      return json(r);
    }
    if (path.endsWith('/models')) {
      return json({
        'data': [
          {'id': 'z-ai/glm-5.3-flash', 'is_tee': true},
        ],
      });
    }
    chats++;
    final exchange = e2ee.open(request.headers, request.bodyBytes);
    lastPlainBody = exchange.plainBody;
    // The receipt covers the decrypted request and the encrypted answer.
    _request = exchange.plainBytes;
    _response = Uint8List.fromList(
      utf8.encode(plainAnswer ? _sse : exchange.sealSse(_sse)),
    );
    return http.Response.bytes(
      _response,
      200,
      headers: {
        'content-type': 'text/event-stream',
        if (!plainAnswer) ...exchange.responseHeaders,
        'x-receipt-id': 'rcpt-fixture',
      },
    );
  });
}

Uint8List _hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

/// Intel PCS stand-in that answers from the recorded collateral (headers
/// URL-encoded like the real service).
http.Client pcsFixtureClient() {
  final collateral = jsonDecode(collateralPcs) as Map<String, dynamic>;
  String chain(String k) => Uri.encodeComponent(collateral[k] as String);
  return MockClient((req) async {
    final p = req.url.path;
    if (p.endsWith('/pckcrl')) {
      return http.Response.bytes(
        _hexBytes(collateral['pck_crl'] as String),
        200,
        headers: {'sgx-pck-crl-issuer-chain': chain('pck_crl_issuer_chain')},
      );
    }
    if (p.endsWith('/tcb')) {
      return http.Response(
        jsonEncode({
          'tcbInfo': jsonDecode(collateral['tcb_info'] as String),
          'signature': collateral['tcb_info_signature'],
        }),
        200,
        headers: {'sgx-tcb-info-issuer-chain': chain('tcb_info_issuer_chain')},
      );
    }
    if (p.endsWith('/qe/identity')) {
      return http.Response(
        jsonEncode({
          'enclaveIdentity': jsonDecode(collateral['qe_identity'] as String),
          'signature': collateral['qe_identity_signature'],
        }),
        200,
        headers: {
          'sgx-enclave-identity-issuer-chain': chain(
            'qe_identity_issuer_chain',
          ),
        },
      );
    }
    if (p.endsWith('.der')) {
      return http.Response.bytes(
        _hexBytes(collateral['root_ca_crl'] as String),
        200,
      );
    }
    return http.Response('?', 404);
  });
}
