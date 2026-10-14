import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import 'tee_support.dart';

/// An [AttestedProvider] against a mock gateway: attestation (probe data),
/// chat (SSE fixture with `x-receipt-id`) and receipts that match the bytes
/// of the exchange.
final class TeeHarness {
  /// Creates the harness.
  TeeHarness({
    FakeAttestationCrypto? crypto,
    this.chatFixture = 'openai/text.sse',
    this.gpu,
    GpuCheckMode gpuMode = GpuCheckMode.off,
    http.Client? chatClient,
  }) : crypto = crypto ?? FakeAttestationCrypto(ed25519Result: true) {
    server = TeeServer({
      'aci/attestation': (_) async {
        final status = attestationStatus;
        return _json(
          status == 200 ? jsonEncode(teeJson('gateway_attestation')) : '{}',
          status,
        );
      },
      'aci/receipts/': (_) async {
        await receiptGate?.future;
        if (receiptFailures > 0) {
          receiptFailures--;
          return _json('{}', 500);
        }
        final receipt = syntheticReceipt(
          lastRequest ?? Uint8List(0),
          lastResponse ?? Uint8List(0),
          receiptEdit,
        );
        return _json(jsonEncode(receipt), 200);
      },
      'chat/completions': (request) {
        lastRequest = request.bodyBytes;
        lastResponse = Uint8List.fromList(utf8.encode(fixture(chatFixture)));
        return http.Response.bytes(
          lastResponse!,
          200,
          headers: {
            'content-type': 'text/event-stream',
            if (sendReceiptId) 'x-receipt-id': 'rcpt-test',
          },
        );
      },
    });
    final client = chatClient ?? server.client;
    final settings = HttpSettings(clock: clock, log: diagnostics.add);
    verifier = PhalaVerifier(
      crypto: this.crypto,
      baseUrl: Uri.parse('https://gateway.test/v1'),
      profileId: 'phala',
      client: client is _Split ? client : _Split(client, server.client),
      settings: settings,
      nonceSource: () => probeNonce,
    );
    provider = AttestedProvider(
      inner: OpenAiChatAdapter(
        baseUrl: Uri.parse('https://gateway.test/v1'),
        credentials: Credentials.apiKey(
          'test-key-attest',
          style: ApiKeyStyle.bearer,
        ),
        defaultModel: 'm',
        client: client is _Split ? client : _Split(client, server.client),
        settings: settings,
        options: const OpenAiOptions(
          extraBody: {
            'provider': {'aci_verified': true},
          },
        ),
      ),
      verifier: verifier,
      profileId: 'phala',
      gpuVerifier: gpu,
      gpuMode: gpuMode,
      logSink: log,
      settings: settings,
      retryDelay: Duration.zero,
    );
  }

  /// Crypto under test.
  final FakeAttestationCrypto crypto;

  /// SSE fixture returned by the chat route.
  String chatFixture;

  /// GPU verifier of the provider.
  final GpuAttestationVerifier? gpu;

  /// The mock gateway.
  late final TeeServer server;

  /// The clock of verifier and provider.
  final FixedClock clock = FixedClock(probeNow);

  /// Audit log.
  final InMemoryAttestationLog log = InMemoryAttestationLog();

  /// `Wendelin/attest:` and transport log lines.
  final List<String> diagnostics = [];

  /// Status of the attestation route.
  int attestationStatus = 200;

  /// Number of receipt requests answered with 500 before success.
  int receiptFailures = 0;

  /// Edit applied to every receipt.
  void Function(Map<String, Object?>)? receiptEdit;

  /// Holds receipt answers until completed.
  Completer<void>? receiptGate;

  /// Whether the chat response carries `x-receipt-id`.
  bool sendReceiptId = true;

  /// Request body of the last chat call.
  Uint8List? lastRequest;

  /// Response body of the last chat call.
  Uint8List? lastResponse;

  late final PhalaVerifier verifier;
  late final AttestedProvider provider;

  /// The request of the tests.
  static ChatRequest request() => ChatRequest(
    systemPrompt: 'Du bist ein Testassistent.',
    messages: [Message.user('Geheimer Prompt-Text')],
    model: 'm',
    maxTokens: 50,
  );

  /// Collects the events of one chat call.
  Future<List<ChatEvent>> chat([CancelToken? cancel]) =>
      provider.chat(request(), cancel: cancel).toList();

  /// Number of chat requests that reached the server.
  int get chatRequests => server.count('chat/completions');
}

http.Response _json(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Routes `/aci/` paths to [_tee] and everything else to [_other].
final class _Split extends http.BaseClient {
  _Split(this._other, this._tee);

  final http.Client _other;
  final http.Client _tee;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      request.url.path.contains('/aci/')
      ? _tee.send(request)
      : _other.send(request);
}

/// A [http.Client] that answers chat calls with [other] and gateway calls
/// (`/aci/`) with [tee]; for the contract suite.
http.Client splitClient(http.Client other, http.Client tee) =>
    _Split(other, tee);
