import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../openai/openai_contract_test.dart' show openAiResponseFor;
import '../support/fake_server.dart';
import 'e2ee_support.dart';
import 'provider_harness.dart';
import 'tee_support.dart';

AttestationFailedException _error(List<ChatEvent> events) =>
    (events.last as ErrorEvent).error as AttestationFailedException;

void main() {
  final service = FakeE2eeService(now: () => probeNow);
  llmProviderContract((scenario) {
    final chat = FakeServer([openAiResponseFor(scenario)]);
    final tee = TeeServer({
      'aci/attestation': jsonBody(attestationFor(service)),
      'aci/sessions/': jsonBody(upToDateSession()),
    });
    return AttestedProvider(
      inner: OpenAiChatAdapter(
        baseUrl: Uri.parse('https://gateway.test/v1'),
        credentials: Credentials.apiKey(
          'test-key-contract',
          style: ApiKeyStyle.bearer,
        ),
        defaultModel: 'contract-model',
        client: splitClient(e2eeFront(service, chat.client), tee.client),
        wireCodec: PhalaE2eeChannel(crypto: FakeAttestationCrypto()),
        options: const OpenAiOptions(
          extraBody: {
            'provider': {'aci_verified': true},
          },
        ),
      ),
      verifier: PhalaVerifier(
        crypto: FakeAttestationCrypto(),
        baseUrl: Uri.parse('https://gateway.test/v1'),
        profileId: 'phala',
        client: tee.client,
        settings: HttpSettings(clock: FixedClock(probeNow)),
        nonceSource: () => probeNonce,
      ),
      profileId: 'phala',
      settings: HttpSettings(clock: FixedClock(probeNow)),
      retryDelay: Duration.zero,
    );
  }, name: 'AttestedProvider');

  group('AttestedProvider: Ablauf', () {
    test(
      'Attestierung vor dem ersten Request, Quittung erst nach dem Stream-Ende',
      () async {
        final h = TeeHarness()..receiptGate = Completer<void>();
        final events = await h.chat();
        expect(events.last, isA<Done>());
        // Done arrived while the receipt was not even answered yet.
        await pumpEventQueue();
        expect(h.server.count('aci/receipts'), 1);
        expect(
          h.server.requests.map((r) => r.url.path.split('/').last).toList(),
          ['attestation', 'completions', 'rcpt-test'],
        );
        var settled = false;
        final report = h.provider.pendingReport().whenComplete(
          () => settled = true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(settled, isFalse, reason: 'Quittung noch nicht geprüft');
        h.receiptGate!.complete();
        expect((await report)?.status, AttestationStatus.green);
      },
    );

    test('Request enthält provider.aci_verified; Stream mit Tool-Aufruf meldet Status nach dem Ende', () async {
      final h = TeeHarness(chatFixture: 'openai/tool_call.sse');
      final reports = <AttestationReport>[];
      h.provider.reports.listen(reports.add);
      final events = await h.chat();
      expect(events.whereType<ToolCallComplete>(), hasLength(1));
      expect(events.last, const Done(StopReason.toolUse));
      expect((jsonDecode(utf8.decode(h.lastRequest!)) as Map)['provider'], {
        'aci_verified': true,
      });
      final report = await h.provider.pendingReport();
      expect(report?.status, AttestationStatus.green);
      await Future<void>.delayed(Duration.zero);
      expect(reports.last, report);
      expect(h.log.entries.last.kind, AttestationLogKind.receipt);
      expect(h.log.entries.last.logId, report?.logId);
      expect(h.log.entries.last.receiptId, 'rcpt-test');
    });

    test(
      'Session wird wiederverwendet; nach not_after neu attestiert',
      () async {
        final h = TeeHarness();
        await h.chat();
        await h.chat();
        expect(h.server.count('aci/attestation'), 1);
        h.clock.set(
          h.provider.session!.notAfter.add(const Duration(seconds: 1)),
        );
        await h.chat();
        expect(h.server.count('aci/attestation'), 2);
      },
    );

    test(
      'Attestierung fehlgeschlagen → kein Request, Provider gesperrt',
      () async {
        final h = TeeHarness(
          crypto: FakeAttestationCrypto(
            quoteError: const QuoteVerificationException('Signatur'),
          ),
        );
        final first = await h.chat();
        final error = _error(first);
        expect(error.stage, 'quote');
        expect(error.unavailable, isFalse);
        expect(error.retryable, isFalse);
        expect(h.provider.locked, isTrue);
        await h.chat();
        expect(h.chatRequests, 0, reason: 'gesperrt: nichts gesendet');
        expect(
          h.server.count('aci/attestation'),
          1,
          reason: 'sperrt ohne neuen Abruf',
        );
      },
    );

    test('reattest hebt die Sperre auf, wenn die Prüfung besteht', () async {
      final crypto = FakeAttestationCrypto(
        ed25519Result: true,
        quoteError: const QuoteVerificationException('x'),
      );
      final h = TeeHarness(crypto: crypto);
      await h.chat();
      expect(h.provider.locked, isTrue);
      crypto.quoteError = null;
      expect((await h.provider.reattest()).status, AttestationStatus.green);
      expect(h.provider.locked, isFalse);
      expect((await h.chat()).last, isA<Done>());
      expect(h.chatRequests, 1);
    });

    test(
      'warmUp prüft vorab; die erste Anfrage attestiert nicht noch einmal',
      () async {
        final h = TeeHarness();
        await h.provider.warmUp();
        expect(h.provider.session, isNotNull);
        expect(h.server.count('aci/attestation'), 1);
        await h.provider.warmUp(); // gültige Sitzung: nichts zu tun
        expect((await h.chat()).last, isA<Done>());
        expect(h.server.count('aci/attestation'), 1);
      },
    );

    test('warmUp hebt eine Sperre nicht auf und wirft nicht', () async {
      final crypto = FakeAttestationCrypto(
        ed25519Result: true,
        quoteError: const QuoteVerificationException('x'),
      );
      final h = TeeHarness(crypto: crypto);
      await h.provider.warmUp();
      expect(h.provider.locked, isTrue);
      crypto.quoteError = null;
      await h.provider.warmUp();
      expect(h.provider.locked, isTrue, reason: 'nur „neu prüfen“ entsperrt');
      expect(h.server.count('aci/attestation'), 1);
    });

    test('Attestierung nicht erreichbar → retryable, nicht gesperrt, später möglich', () async {
      final h = TeeHarness()..attestationStatus = 503;
      final error = _error(await h.chat());
      expect(error.unavailable, isTrue);
      expect(error.retryable, isTrue);
      expect(h.provider.locked, isFalse);
      expect(h.chatRequests, 0);
      h.attestationStatus = 200;
      expect((await h.chat()).last, isA<Done>());
    });

    test('Abbruch während der Attestierung: Cancelled, kein Request', () async {
      final h = TeeHarness();
      final token = CancelToken()..cancel();
      final events = await h.chat(token);
      expect((events.last as ErrorEvent).error, isA<CancelledException>());
      expect(h.chatRequests, 0);
    });
  });

  group('AttestedProvider: Quittung', () {
    test(
      'ungültige Quittung → rot, weitere Anfragen gesperrt ohne Request',
      () async {
        final h = TeeHarness()
          ..receiptEdit = (r) {
            final e = (r['event_log']! as List).cast<Map<String, Object?>>();
            e.firstWhere((x) => x['type'] == 'upstream.verified')['result'] =
                'failed';
          };
        await h.chat();
        final report = await h.provider.pendingReport();
        expect(report?.status, AttestationStatus.red);
        expect(h.provider.locked, isTrue);
        expect(h.log.entries.last.status, AttestationStatus.red);
        expect(
          h.log.entries.last.stages
              .where((s) => s.outcome == StageOutcome.fail)
              .map((s) => s.stage),
          [AttestationStage.upstream],
        );
        final before = h.chatRequests;
        final blocked = _error(await h.chat());
        expect(blocked.stage, 'receipt.upstream');
        expect(
          h.chatRequests,
          before,
          reason: 'gesperrter Provider sendet nichts',
        );
      },
    );

    test(
      'Netzfehler: gelber Zwischenstand, dann grün beim 2. Versuch',
      () async {
        final h = TeeHarness()..receiptFailures = 1;
        final seen = <AttestationStatus>[];
        h.provider.reports.listen((r) => seen.add(r.status));
        await h.chat();
        final report = await h.provider.pendingReport();
        expect(report?.status, AttestationStatus.green);
        expect(h.server.count('aci/receipts'), 2);
        await pumpEventQueue();
        expect(
          seen,
          containsAllInOrder([
            AttestationStatus.yellow,
            AttestationStatus.green,
          ]),
        );
        expect(h.provider.locked, isFalse);
      },
    );

    test('Netzfehler: nach 3 Versuchen rot und gesperrt', () async {
      final h = TeeHarness()..receiptFailures = 10;
      await h.chat();
      final report = await h.provider.pendingReport();
      expect(report?.status, AttestationStatus.red);
      expect(h.server.count('aci/receipts'), 3);
      expect(h.provider.locked, isTrue);
    });

    test('Antwort ohne x-receipt-id → rot', () async {
      final h = TeeHarness()..sendReceiptId = false;
      await h.chat();
      expect((await h.provider.pendingReport())?.status, AttestationStatus.red);
      expect(h.server.count('aci/receipts'), 0);
    });

    test('Pinning-Wechsel: Antwort rot, nicht gesperrt, nächste Anfrage attestiert neu mit Hinweis', () async {
      final h = TeeHarness()
        ..receiptEdit = (r) =>
            r['workload_keyset_digest'] = 'sha256:${'00' * 32}';
      await h.chat();
      final report = await h.provider.pendingReport();
      expect(report?.status, AttestationStatus.red);
      expect(report?.detail, contains('Update'));
      expect(h.provider.locked, isFalse);
      h.receiptEdit = null;
      await h.chat();
      expect(h.server.count('aci/attestation'), 2);
      expect(
        (await h.provider.pendingReport())?.status,
        AttestationStatus.green,
      );
    });

    test(
      'Fehler im Stream: kein Receipt-Abruf, pendingReport ist null',
      () async {
        final h = TeeHarness(chatFixture: 'openai/error_during_tool_call.sse');
        final events = await h.chat();
        expect(events.last, isA<ErrorEvent>());
        expect(await h.provider.pendingReport(), isNull);
        expect(h.server.count('aci/receipts'), 0);
      },
    );
  });

  group('AttestedProvider: Diagnose und Datenschutz', () {
    test('Log und Audit-Protokoll enthalten Stufen, aber keine Prompt-, Antwort- oder Quittungsinhalte', () async {
      final h = TeeHarness();
      await h.chat();
      await h.provider.pendingReport();
      final text = [
        ...h.diagnostics,
        jsonEncode([for (final e in h.log.entries) e.toJson()]),
      ].join('\n');
      expect(h.diagnostics, contains('Wendelin/attest: session quote=pass'));
      expect(
        h.diagnostics,
        contains('Wendelin/attest: receipt receipt.signature=pass'),
      );
      expect(h.diagnostics, contains('Wendelin/attest: receipt green'));
      for (final forbidden in [
        'Geheimer Prompt-Text',
        'Hallo!',
        'Wendelin.',
        'test-key-attest',
        'body_hash',
        'rcpt-6120b54538a61ef7718efd33',
      ]) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}
