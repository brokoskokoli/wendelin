import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import 'e2ee_support.dart';
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
    this.tlsPin,
    http.Client Function(http.Client base, {required bool enforce})? pinWrap,
    Uri? baseUrl,
    bool noTools = false,
  }) : crypto = crypto ?? FakeAttestationCrypto(ed25519Result: true) {
    server = TeeServer({
      'aci/attestation': (_) async {
        final status = attestationStatus;
        return _json(status == 200 ? jsonEncode(attestation) : '{}', status);
      },
      'aci/sessions/': (_) async {
        if (sessionFailures > 0) {
          sessionFailures--;
          return _json('{}', 500);
        }
        return _json(jsonEncode(sessionDoc ?? upToDateSession()), 200);
      },
      'aci/receipts/': (request) async {
        await receiptGate?.future;
        if (receiptFailures > 0) {
          receiptFailures--;
          return _json('{}', receiptFailureStatus);
        }
        final known = knownReceiptIds;
        if (known != null && !known.contains(request.url.pathSegments.last)) {
          return _json('{}', 404);
        }
        final receipt = syntheticReceipt(
          lastRequest ?? Uint8List(0),
          lastResponse ?? Uint8List(0),
          (r) {
            r['workload_keyset_digest'] = attestation['workload_keyset_digest'];
            receiptEdit?.call(r);
          },
          sessionDoc ?? upToDateSession(),
        );
        return _json(jsonEncode(receipt), 200);
      },
      'chat/completions': (request) {
        final FakeE2eeExchange exchange;
        try {
          exchange = e2ee.open(request.headers, request.bodyBytes);
        } on E2eeRejection catch (e) {
          return _json(e.body, 400);
        }
        lastExchange = exchange;
        lastRequest = exchange.plainBytes;
        final plain = fixture(chatFixture);
        lastResponse = Uint8List.fromList(
          utf8.encode(
            sealResponse?.call(exchange, plain) ?? exchange.sealSse(plain),
          ),
        );
        return http.Response.bytes(
          lastResponse!,
          200,
          headers: {
            'content-type': 'text/event-stream',
            ...(responseHeaders?.call(exchange) ?? exchange.responseHeaders),
            if (sendReceiptId) 'x-receipt-id': 'rcpt-test',
          },
        );
      },
    });
    final client = chatClient ?? server.client;
    final url = baseUrl ?? Uri.parse('https://gateway.test/v1');
    final tee = pinWrap == null
        ? server.client
        : pinWrap(server.client, enforce: false);
    final content = pinWrap == null ? client : pinWrap(client, enforce: true);
    final settings = HttpSettings(clock: clock, log: diagnostics.add);
    attestation = attestationFor(e2ee);
    verifier = PhalaVerifier(
      crypto: this.crypto,
      baseUrl: url,
      profileId: 'phala',
      client: client is _Split ? client : _Split(client, tee),
      tlsPin: tlsPin,
      settings: settings,
      nonceSource: () => probeNonce,
    );
    provider = AttestedProvider(
      inner: OpenAiChatAdapter(
        baseUrl: url,
        credentials: Credentials.apiKey(
          'test-key-attest',
          style: ApiKeyStyle.bearer,
        ),
        defaultModel: 'm',
        client: client is _Split ? client : _Split(content, tee),
        settings: settings,
        wireCodec: PhalaE2eeChannel(crypto: this.crypto),
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
      tlsPin: tlsPin,
      noTools: noTools,
    );
  }

  /// The service side of the end-to-end encryption (WP62); its key is the
  /// one in the attested keyset.
  final FakeE2eeService e2ee = FakeE2eeService(now: () => probeNow);

  /// The attestation document the gateway serves (key of [e2ee]).
  late Map<String, Object?> attestation;

  /// The decrypted request of the last chat call.
  FakeE2eeExchange? lastExchange;

  /// Replaces how the answer is encrypted (default: [FakeE2eeExchange.sealSse]).
  String Function(FakeE2eeExchange exchange, String plainSse)? sealResponse;

  /// Replaces the E2EE response headers (default: proper ones).
  Map<String, String> Function(FakeE2eeExchange exchange)? responseHeaders;

  /// Pin state shared by verifier and provider (WP61).
  final TlsPinGate? tlsPin;

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

  /// HTTP status of the failing receipt requests.
  int receiptFailureStatus = 500;

  /// If set, receipt ids not in it answer 404.
  Set<String>? knownReceiptIds;

  /// Upstream session served; `null` = up-to-date variant of the probe.
  Map<String, Object?>? sessionDoc;

  /// Number of session requests answered with 500 before success.
  int sessionFailures = 0;

  /// Edit applied to every receipt.
  void Function(Map<String, Object?>)? receiptEdit;

  /// Holds receipt answers until completed.
  Completer<void>? receiptGate;

  /// Whether the chat response carries `x-receipt-id`.
  bool sendReceiptId = true;

  /// Decrypted request body of the last chat call (what the receipt hashes).
  Uint8List? lastRequest;

  /// Response body of the last chat call as it went over the wire.
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
