import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'test_env.dart';

/// [AttestationVerifier] with scripted results (no network, no crypto).
final class ScriptedVerifier implements AttestationVerifier {
  /// Result of the next [attest] calls.
  List<StageResult> sessionStages = const [
    StageResult.pass(AttestationStage.quote),
    StageResult.pass(AttestationStage.nonceBinding),
  ];

  /// Outcomes of the receipt attempts (the last one repeats).
  List<ReceiptResult> receipts = [
    const ReceiptResult(
      stages: [StageResult.pass(AttestationStage.receiptSignature)],
      status: AttestationStatus.green,
    ),
  ];

  /// Completes later than the answer: the receipt check waits for it.
  Completer<void>? receiptGate;

  /// Number of [attest] calls.
  int attests = 0;

  int _receipt = 0;

  @override
  Future<AttestationResult> attest() async {
    attests++;
    final failed = sessionStages.any((s) => s.outcome == StageOutcome.fail);
    return AttestationResult(
      status: failed ? AttestationStatus.red : AttestationStatus.green,
      stages: sessionStages,
      session: failed
          ? null
          : AttestedSession(
              keysetDigest: 'sha256:k',
              notAfter: testNow.add(const Duration(hours: 1)),
              receiptKeys: const {},
              repoCommit: 'abc',
              composeHash: 'c0ffee',
              attestedAt: testNow,
            ),
    );
  }

  @override
  Future<ReceiptResult> verifyReceipt(
    ReceiptRef ref,
    Uint8List requestBytes,
    Uint8List responseBytes,
  ) async {
    await receiptGate?.future;
    final i = _receipt < receipts.length ? _receipt : receipts.length - 1;
    _receipt++;
    return receipts[i];
  }
}

/// A receipt result that fails at [stage] with [code].
ReceiptResult failedReceipt(AttestationStage stage, {String? code}) =>
    ReceiptResult(
      stages: [StageResult.fail(stage, 'abgelehnt', code: code)],
      status: AttestationStatus.red,
    );

const _sse =
    'data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{"role":"assistant","content":"Ruhig: 0,4 m Welle."},'
    '"finish_reason":null}]}\n\n'
    'data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,'
    '"delta":{},"finish_reason":"stop"}]}\n\n'
    'data: [DONE]\n\n';

/// Chat server of the scripted TEE provider: one SSE answer with a receipt id.
final class ScriptedGateway {
  /// Chat requests received.
  int requests = 0;

  /// The HTTP client.
  late final http.Client client = MockClient((request) async {
    if (request.url.path.endsWith('/models')) {
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'z-ai/glm-5.3-flash', 'is_tee': true},
            {'id': 'openai/gpt-nicht-tee', 'is_tee': false},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    requests++;
    return http.Response.bytes(
      utf8.encode(_sse),
      200,
      headers: {
        'content-type': 'text/event-stream',
        'x-receipt-id': 'rcpt-$requests',
      },
    );
  });
}

/// An [AttestedProvider] over [verifier] and [gateway] (profile `phala`).
AttestedProvider scriptedTee({
  required ScriptedVerifier verifier,
  required ScriptedGateway gateway,
  GpuAttestationVerifier? gpu,
  GpuCheckMode gpuMode = GpuCheckMode.off,
  AttestationLogSink? logSink,
  bool fallbackOnFailure = false,
}) => AttestedProvider(
  inner: OpenAiChatAdapter(
    baseUrl: Uri.parse('https://gateway.test/v1'),
    credentials: Credentials.apiKey('test-key', style: ApiKeyStyle.bearer),
    defaultModel: 'z-ai/glm-5.3-flash',
    client: gateway.client,
    options: const OpenAiOptions(
      teeModelsOnly: true,
      extraBody: {
        'provider': {'aci_verified': true},
      },
    ),
    capabilities: const ProviderCapabilities(
      tools: true,
      streaming: true,
      tee: true,
    ),
  ),
  verifier: verifier,
  profileId: 'phala',
  gpuVerifier: gpu,
  gpuMode: gpuMode,
  logSink: logSink,
  settings: HttpSettings(clock: FixedClock(testNow)),
  retryDelay: Duration.zero,
  fallbackOnFailure: fallbackOnFailure,
);
