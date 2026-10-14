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
