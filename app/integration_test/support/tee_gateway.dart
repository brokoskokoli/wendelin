import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_providers/fakes.dart';

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

  Uint8List _request = Uint8List(0);
  Uint8List _response = Uint8List(0);

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
    _request = request.bodyBytes;
    _response = Uint8List.fromList(utf8.encode(_sse));
    return http.Response.bytes(
      _response,
      200,
      headers: {
        'content-type': 'text/event-stream',
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
