import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/testing.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import 'e2ee_support.dart';
import 'provider_harness.dart';
import 'tee_support.dart';

final _service = FakeE2eeService();

/// Verifier whose behaviour the test scripts.
final class ScriptedVerifier implements AttestationVerifier {
  Future<AttestationResult> Function() onAttest = () async => AttestationResult(
    status: AttestationStatus.green,
    stages: const [],
    session: AttestedSession(
      keysetDigest: 'sha256:x',
      notAfter: DateTime.utc(2100),
      receiptKeys: const {},
      repoCommit: null,
      composeHash: 'c',
      attestedAt: DateTime.utc(2026),
      e2eeKey: keyOf(_service),
    ),
  );
  Future<ReceiptResult> Function(ReceiptRef) onReceipt = (ref) async =>
      const ReceiptResult(stages: [], status: AttestationStatus.green);

  @override
  Future<AttestationResult> attest() => onAttest();

  @override
  Future<ReceiptResult> verifyReceipt(
    ReceiptRef ref,
    Uint8List requestBytes,
    Uint8List responseBytes,
  ) => onReceipt(ref);
}

/// Provider over a mock chat server (receipt id from the user text).
(AttestedProvider, TeeServer) _provider(ScriptedVerifier verifier) {
  final server = TeeServer({
    'chat/completions': (request) {
      final body = utf8.decode(request.bodyBytes);
      final id = body.contains('BBB') ? 'rcpt-B' : 'rcpt-A';
      return http.Response(
        fixture('openai/text.sse'),
        200,
        headers: {'content-type': 'text/event-stream', 'x-receipt-id': id},
      );
    },
  });
  return (
    AttestedProvider(
      inner: OpenAiChatAdapter(
        baseUrl: Uri.parse('https://gateway.test/v1'),
        credentials: Credentials.apiKey('k', style: ApiKeyStyle.bearer),
        defaultModel: 'm',
        client: e2eeFront(_service, server.client),
        wireCodec: PhalaE2eeChannel(crypto: FakeAttestationCrypto()),
        options: const OpenAiOptions(
          extraBody: {
            'provider': {'aci_verified': true},
          },
        ),
      ),
      verifier: verifier,
      profileId: 'p',
      retryDelay: Duration.zero,
    ),
    server,
  );
}

ChatRequest _req(String text) =>
    ChatRequest(messages: [Message.user(text)], model: 'm', maxTokens: 5);

void main() {
  group('Ausnahmen im Verifier gelten als rot (fail-closed)', () {
    test(
      'attest wirft: Anfrage nicht gesendet, gesperrt, Stufe internal',
      () async {
        final v = ScriptedVerifier()..onAttest = () => throw StateError('boom');
        final (p, server) = _provider(v);
        final events = await p.chat(_req('Hi')).toList();
        final error = (events.last as ErrorEvent).error;
        expect(error, isA<AttestationFailedException>());
        expect((error as AttestationFailedException).stage, 'internal');
        expect(error.unavailable, isFalse);
        expect(p.locked, isTrue);
        expect(server.count('chat/completions'), 0);
        // Locked: the next request is refused without asking the verifier.
        expect((await p.chat(_req('Hi')).toList()).last, isA<ErrorEvent>());
        expect(server.count('chat/completions'), 0);
      },
    );

    test('verifyReceipt wirft: Bericht rot und Sperre', () async {
      final v = ScriptedVerifier()..onReceipt = (_) => throw StateError('boom');
      final (p, server) = _provider(v);
      final events = await p.chat(_req('Hi')).toList();
      expect(events.last, isA<Done>());
      expect(await p.reportFor(_req('unbekannt')), isNull);
      final real = await p.pendingReport();
      expect(real?.status, AttestationStatus.red);
      expect(p.locked, isTrue);
      expect((await p.chat(_req('Hi')).toList()).last, isA<ErrorEvent>());
      expect(server.count('chat/completions'), 1);
    });
  });

  test('Bericht ist pro chat-Aufruf gebunden (parallele Läufe)', () async {
    final gateA = Completer<void>();
    final v = ScriptedVerifier()
      ..onReceipt = (ref) async {
        if (ref.id == 'rcpt-A') await gateA.future;
        return ReceiptResult(
          stages: ref.id == 'rcpt-B'
              ? const [StageResult.fail(AttestationStage.receiptSignature, 'x')]
              : const [],
          status: ref.id == 'rcpt-B'
              ? AttestationStatus.red
              : AttestationStatus.green,
        );
      };
    final (p, _) = _provider(v);
    final a = _req('AAA');
    final b = _req('BBB');
    final runA = p.chat(a).toList();
    final runB = p.chat(b).toList();
    await Future.wait([runA, runB]);
    // B (red) is final first; A's receipt still waits.
    expect((await p.reportFor(b))?.status, AttestationStatus.red);
    gateA.complete();
    expect(
      (await p.reportFor(a))?.status,
      AttestationStatus.green,
      reason: 'A sieht nicht das rote Ergebnis von B',
    );
  });

  test('Decorator verlangt provider.aci_verified in extraBody', () {
    AttestedProvider build(OpenAiOptions options) => AttestedProvider(
      inner: OpenAiChatAdapter(
        baseUrl: Uri.parse('https://gateway.test/v1'),
        credentials: Credentials.apiKey('k', style: ApiKeyStyle.bearer),
        defaultModel: 'm',
        client: TeeServer({}).client,
        wireCodec: PhalaE2eeChannel(crypto: FakeAttestationCrypto()),
        options: options,
      ),
      verifier: ScriptedVerifier(),
      profileId: 'p',
    );
    expect(() => build(const OpenAiOptions()), throwsArgumentError);
    expect(
      () => build(
        const OpenAiOptions(
          extraBody: {
            'provider': {'aci_verified': false},
          },
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => build(
        const OpenAiOptions(
          extraBody: {
            'provider': {'aci_verified': true},
          },
        ),
      ),
      returnsNormally,
    );
  });

  group('Grenzwerte', () {
    int notAfter() =>
        ((teeJson('gateway_attestation')['attestation']!
                    as Map<String, Object?>)['workload_keyset']!
                as Map<String, Object?>)['not_after']!
            as int;

    Future<AttestationResult> attestAt(int epoch) => probeVerifier(
      attestationServer(),
      FakeAttestationCrypto(),
      now: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
    ).attest();

    test(
      'not_after: eine Sekunde davor gültig, genau zur Grenze abgelaufen',
      () async {
        final before = await attestAt(notAfter() - 1);
        expect(
          before.stages.singleWhere(
            (s) => s.stage == AttestationStage.freshness,
          ),
          isA<StageResult>().having((s) => s.outcome, 'o', StageOutcome.pass),
        );
        final at = await attestAt(notAfter());
        expect(at.firstProblem?.stage, AttestationStage.freshness);
      },
    );

    test(
      'Session im Provider: zur Grenze not_after wird neu attestiert',
      () async {
        final h = TeeHarness();
        await h.chat();
        final limit = h.provider.session!.notAfter;
        h.clock.set(limit.subtract(const Duration(seconds: 1)));
        await h.chat();
        expect(h.server.count('aci/attestation'), 1);
        h.clock.set(limit);
        await h.chat();
        expect(h.server.count('aci/attestation'), 2);
      },
    );

    test(
      'report_data im Dokument weicht ab (Quote stimmt): Nonce-Bindung rot',
      () async {
        final doc = copyJson(teeJson('gateway_attestation'));
        final att = doc['attestation']! as Map<String, Object?>;
        final rd = att['report_data']! as String;
        att['report_data'] =
            '${rd.startsWith('0') ? '1' : '0'}${rd.substring(1)}';
        final r = await probeVerifier(
          attestationServer(doc),
          FakeAttestationCrypto(),
        ).attest();
        expect(r.status, AttestationStatus.red);
        expect(r.firstProblem?.stage, AttestationStage.nonceBinding);
      },
    );

    test('andere Nonce als im Quote: Nonce-Bindung rot', () async {
      final r = await probeVerifier(
        attestationServer(),
        FakeAttestationCrypto(),
        nonce: Uint8List.fromList(List.filled(32, 0x01)),
      ).attest();
      expect(r.firstProblem?.stage, AttestationStage.nonceBinding);
    });
  });
}
