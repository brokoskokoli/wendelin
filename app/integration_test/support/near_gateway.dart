import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_providers/fakes.dart';

import 'tee_fixtures.g.dart';

/// Nonce of the recorded NEAR report (the quotes bind it).
final nearNonce = Uint8List.fromList([
  for (var i = 0; i < 64; i += 2)
    int.parse(
      'f3b426ddde16000e004951b8f083930703e5570e487eca22bf83cb84e7f338e0'
          .substring(i, i + 2),
      radix: 16,
    ),
]);

/// Check time of the recording (the Intel collateral is valid then).
final nearNow = DateTime.fromMillisecondsSinceEpoch(
  1792100512 * 1000,
  isUtc: true,
);

/// Ed25519 key of the recorded model (E2EE key and receipt signer). Nobody
/// has its secret, so the device test's crypto encrypts to the fixture
/// service instead (see `near_app_e2e_test.dart`); requests still name this
/// key in `X-Model-Pub-Key`.
const nearRecordedModelKeyHex =
    '5a0210f2442c79355784f9de021985429561da5bacc3a4424b01ac52b7e0caff';

/// SPKI hash the recorded gateway quote binds for `cloud-api.near.ai`.
const nearGatewayPin =
    '73862c254372091cc6895b900111503860694f8916ebf0c63b18d245ba8ba5ad';

const nearModelId = 'z-ai/glm-5.3-flash';

const _sse =
    'data: {"id":"near-chat-1","object":"chat.completion.chunk","choices":'
    '[{"index":0,"delta":{"role":"assistant","content":"Ruhig: 0,4 m Welle."},'
    '"finish_reason":null}]}\n\n'
    'data: {"id":"near-chat-1","object":"chat.completion.chunk","choices":'
    '[{"index":0,"delta":{},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

String _sha(Uint8List bytes) => FakeAttestationCrypto()
    .sha256(bytes)
    .map((v) => v.toRadixString(16).padLeft(2, '0'))
    .join();

/// Fixture transport of the NEAR AI cloud: the recorded attestation report
/// (real quotes), a service that decrypts requests and encrypts answers with
/// the real protocol, and signatures built from the bytes of the exchange.
/// [tamper] changes the signed text before it is served.
final class NearFixtureGateway {
  /// Creates the gateway.
  NearFixtureGateway();

  /// Changes the next signature documents, if set.
  void Function(Map<String, Object?> signature)? tamper;

  /// Chat requests received.
  int chats = 0;

  /// The service side of the E2EE protocol (accepts the recorded key).
  final FakeNearService service = FakeNearService(
    alsoAcceptModelKeys: {nearRecordedModelKeyHex},
  );

  /// Answers in plaintext (a service that ignores E2EE).
  bool plainAnswer = false;

  /// The decrypted request of the last chat call.
  Map<String, Object?>? lastPlainBody;

  /// The request body as it was on the wire.
  String? lastWire;

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
      if (request.url.queryParameters.containsKey('include_tls_fingerprint')) {
        return json(jsonDecode(nearReport));
      }
      // GPU evidence: only the nonce binding is checked locally (mode „Aus“).
      return json({
        'model_attestations': [
          {
            'nvidia_payload': jsonEncode({
              'nonce': request.url.queryParameters['nonce'],
              'evidence_list': <Object?>[],
            }),
          },
        ],
      });
    }
    if (path.contains('signature/')) {
      final doc = <String, Object?>{
        'text': '$nearModelId:${_sha(_request)}:${_sha(_response)}',
        'signature': '00' * 64,
        'signing_address': nearRecordedModelKeyHex,
        'signing_algo': 'ed25519',
        'signature_kind': 'provider_tee',
      };
      tamper?.call(doc);
      return json(doc);
    }
    chats++;
    lastWire = request.body;
    final exchange = service.open(request.headers, request.bodyBytes);
    lastPlainBody = exchange.request;
    _request = request.bodyBytes;
    _response = Uint8List.fromList(
      utf8.encode(plainAnswer ? _sse : exchange.sealSse(_sse)),
    );
    return http.Response.bytes(
      _response,
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
}
