import 'dart:convert';

import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/e2ee_v2.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart' show fixture;
import 'e2ee_support.dart';
import 'provider_harness.dart';
import 'tee_support.dart';

AttestationFailedException _error(List<ChatEvent> events) =>
    (events.last as ErrorEvent).error as AttestationFailedException;

String _text(List<ChatEvent> events) =>
    events.whereType<TextDelta>().map((e) => e.text).join();

void main() {
  group('Phala E2EE v2: Anfrage', () {
    test('der Server sieht keinen Klartext der Nachrichten, der Dienst entschlüsselt sie', () async {
      final h = TeeHarness();
      final events = await h.chat();
      expect(events.last, isA<Done>());
      final raw = h.server.requests
          .firstWhere((r) => r.url.path.endsWith('chat/completions'))
          .body;
      expect(raw, isNot(contains('Geheimer Prompt-Text')));
      expect(raw, isNot(contains('Du bist ein Testassistent')));
      final json = jsonDecode(raw) as Map<String, Object?>;
      expect(json['model'], 'm');
      final messages = (json['messages']! as List).cast<Map<String, Object?>>();
      expect(messages, hasLength(2));
      for (final m in messages) {
        expect(m['content'], matches(RegExp(r'^[0-9a-f]{120,}$')));
      }
      final plain = h.lastExchange!.plainBody['messages']! as List;
      expect(plain.map((m) => (m as Map)['content']), [
        'Du bist ein Testassistent.',
        'Geheimer Prompt-Text',
      ]);
    });

    test(
      'Header sind gesetzt, Bearer-Key bleibt, kein Legacy-Header',
      () async {
        final h = TeeHarness();
        await h.chat();
        final r = h.server.requests.firstWhere(
          (r) => r.url.path.endsWith('chat/completions'),
        );
        expect(r.headers['x-e2ee-version'], '2');
        expect(r.headers['x-e2ee-nonce'], matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(r.headers['x-model-pub-key'], h.e2ee.publicKeyHex);
        expect(r.headers['authorization'], startsWith('Bearer '));
        expect(r.headers.containsKey('x-signing-algo'), isFalse);
      },
    );

    test('Schlüssel stammt aus dem geprüften Keyset (Sitzung)', () async {
      final h = TeeHarness();
      await h.chat();
      expect(h.provider.session!.e2eeKey!.publicKey, h.e2ee.key.public);
      expect(h.provider.session!.e2eeKey!.algo, E2eeProtocolV2.algo);
    });

    test('jede Anfrage bekommt neue Nonce und neue Verschlüsselung (Replay-Schutz)', () async {
      final h = TeeHarness();
      await h.chat();
      await h.chat();
      final nonces = [
        for (final r in h.server.requests)
          if (r.url.path.endsWith('chat/completions'))
            r.headers['x-e2ee-nonce'],
      ];
      expect(nonces.toSet(), hasLength(2));
      final bodies = [
        for (final r in h.server.requests)
          if (r.url.path.endsWith('chat/completions')) r.body,
      ];
      expect(bodies[0], isNot(bodies[1]));
    });

    test('Wiederholung durch den Transport (stream_options abgelehnt) verschlüsselt neu', () async {
      final h = TeeHarness();
      var calls = 0;
      h.server.routes['chat/completions'] = (request) {
        calls++;
        if (calls == 1) {
          // The first try is refused like a gateway that does not know
          // stream_options; the adapter sends again.
          return http.Response(
            jsonEncode({
              'error': {'message': 'Unknown parameter: stream_options'},
            }),
            400,
          );
        }
        final e = h.e2ee.open(request.headers, request.bodyBytes);
        return http.Response(
          e.sealSse(fixture('openai/text.sse')),
          200,
          headers: {'content-type': 'text/event-stream', ...e.responseHeaders},
        );
      };
      final events = await h.chat();
      expect(calls, 2);
      expect(_text(events), 'Hallo! Ich bin Wendelin.');
    });

    test('Prüfaufruf (Health-Check) ist ebenfalls verschlüsselt', () async {
      final h = TeeHarness();
      await h.provider.test();
      final raws = [
        for (final r in h.server.requests)
          if (r.url.path.endsWith('chat/completions')) r.body,
      ];
      expect(raws, isNotEmpty);
      for (final raw in raws) {
        for (final m in (jsonDecode(raw) as Map)['messages'] as List) {
          expect((m as Map)['content'], matches(RegExp(r'^[0-9a-f]+$')));
        }
      }
    });

    test(
      'Dienst lehnt ab (z. B. Uhrzeit): Fehler, keine Klartext-Wiederholung',
      () async {
        final h = TeeHarness();
        h.clock.set(
          probeNow.add(const Duration(minutes: 10)),
        ); // skew vs. service
        final events = await h.chat();
        expect(events.last, isA<ErrorEvent>());
        expect(h.chatRequests, 1);
        expect(
          h.server.requests
              .where((r) => r.url.path.endsWith('chat/completions'))
              .every((r) => !r.body.contains('Geheimer Prompt-Text')),
          isTrue,
        );
      },
    );
  });

  group('Phala E2EE v2: Antwort', () {
    test('verschlüsselter Stream wird Delta für Delta entschlüsselt', () async {
      final h = TeeHarness();
      final events = await h.chat();
      expect(_text(events), 'Hallo! Ich bin Wendelin.');
      expect(events.last, const Done(StopReason.endTurn));
      final wire = utf8.decode(h.lastResponse!);
      expect(wire, isNot(contains('Hallo')));
      expect(wire, isNot(contains('Wendelin.')));
      expect(events.whereType<UsageEvent>(), isNotEmpty);
    });

    test('Reasoning-Deltas werden entschlüsselt', () async {
      final h = TeeHarness(chatFixture: 'openai/reasoning.sse');
      final events = await h.chat();
      final thinking = events.whereType<ThinkingDelta>().map((e) => e.text);
      expect(thinking, isNotEmpty);
      final wire = utf8.decode(h.lastResponse!);
      for (final t in thinking) {
        expect(wire, isNot(contains(t)));
      }
    });

    test('tool_calls bleiben Klartext und funktionieren', () async {
      final h = TeeHarness(chatFixture: 'openai/tool_call.sse');
      final events = await h.chat();
      expect(events.whereType<ToolCallComplete>(), hasLength(1));
    });

    test('Antwort ohne E2EE-Header (X-E2EE-Applied: false): Fehler, Klartext nie sichtbar', () async {
      final h = TeeHarness();
      h
        ..responseHeaders = ((_) => {'x-e2ee-applied': 'false'})
        ..sealResponse = ((_, plain) => plain);
      final events = await h.chat();
      expect(events.whereType<TextDelta>(), isEmpty);
      expect(_error(events).stage, 'e2ee.response');
      expect(h.provider.locked, isFalse);
    });

    test('Header fehlen ganz', () async {
      final h = TeeHarness();
      h.responseHeaders = (_) => {};
      final events = await h.chat();
      expect(events.whereType<TextDelta>(), isEmpty);
      expect(_error(events).stage, 'e2ee.response');
    });

    test(
      'Header sagen verschlüsselt, Felder sind aber Klartext: Abbruch',
      () async {
        final h = TeeHarness();
        h.sealResponse = (_, plain) => plain;
        final events = await h.chat();
        expect(events.whereType<TextDelta>(), isEmpty);
        expect(_error(events).stage, 'e2ee.response');
      },
    );

    test('Entschlüsselungsfehler in der Mitte des Streams: Abbruch, schon Gezeigtes bleibt unverändert', () async {
      final h = TeeHarness();
      h.sealResponse = (e, plain) {
        final sealed = e.sealSse(plain).split('\n');
        final i = sealed.lastIndexWhere(
          (l) => l.contains('"delta":{"content"'),
        );
        final line = jsonDecode(sealed[i].substring(6)) as Map;
        final delta = ((line['choices'] as List).single as Map)['delta'] as Map;
        final c = delta['content'] as String;
        delta['content'] =
            '${c.substring(0, c.length - 1)}${c.endsWith('0') ? '1' : '0'}';
        sealed[i] = 'data: ${jsonEncode(line)}';
        return sealed.join('\n');
      };
      final events = await h.chat();
      expect(_text(events), 'Hallo! ');
      expect(_error(events).stage, 'e2ee.response');
      expect(events.whereType<Done>(), isEmpty);
    });

    test('Fehler lässt Sitzung neu prüfen, sperrt aber nicht; kein Anbieterwechsel', () async {
      final h = TeeHarness();
      h.sealResponse = (_, plain) => plain;
      await h.chat();
      expect(h.provider.locked, isFalse);
      expect(h.provider.session, isNull);
      h.sealResponse = null;
      final events = await h.chat();
      expect(_text(events), 'Hallo! Ich bin Wendelin.');
      expect(h.server.count('aci/attestation'), 2);
    });

    test(
      'anderes Keyset im Antwort-Header: Fehler und neue Attestierung',
      () async {
        final h = TeeHarness();
        h.responseHeaders = (e) => {
          ...e.responseHeaders,
          'x-aci-keyset-digest': 'sha256:${'00' * 32}',
        };
        final events = await h.chat();
        expect(_error(events).stage, 'e2ee.keyset');
        expect(h.provider.session, isNull);
      },
    );

    test('passender Keyset-Header ist unauffällig', () async {
      final h = TeeHarness();
      h.responseHeaders = (e) => {
        ...e.responseHeaders,
        'x-aci-keyset-digest':
            h.attestation['workload_keyset_digest']! as String,
      };
      expect(_text(await h.chat()), 'Hallo! Ich bin Wendelin.');
    });
  });

  group('Phala E2EE v2: Schlüssel aus der Attestierung', () {
    test('Keyset ohne x25519-Schlüssel: Attestierung rot (Stufe e2ee.key), nichts gesendet', () async {
      final h = TeeHarness();
      h.attestation = attestationFor(
        h.e2ee,
        editKeyset: (k) =>
            ((k['e2ee_public_keys']! as List).first
                    as Map<String, Object?>)['algo'] =
                'secp256k1-aes-256-gcm-hkdf-sha256',
      );
      final events = await h.chat();
      expect(_error(events).stage, 'e2ee.key');
      expect(h.provider.locked, isTrue);
      expect(h.chatRequests, 0);
    });

    test('Dienst nennt Version 2 nicht: rot, nichts gesendet', () async {
      final h = TeeHarness();
      h.attestation['service_capabilities'] = {
        'supported_e2ee_versions': ['3'],
      };
      final events = await h.chat();
      expect(_error(events).stage, 'e2ee.key');
      expect(h.chatRequests, 0);
    });

    test('Keyset ohne e2ee_public_keys: rot', () async {
      final h = TeeHarness();
      h.attestation = attestationFor(
        h.e2ee,
        editKeyset: (k) => k.remove('e2ee_public_keys'),
      );
      final events = await h.chat();
      expect(_error(events).stage, 'e2ee.key');
      expect(h.chatRequests, 0);
    });

    test('abgelaufenes Keyset: neu attestieren, vor Ablauf kein Senden mit altem Schlüssel', () async {
      final h = TeeHarness();
      await h.chat();
      expect(h.server.count('aci/attestation'), 1);
      h.clock.set(
        h.provider.session!.notAfter.subtract(const Duration(seconds: 1)),
      );
      await h.chat();
      expect(h.server.count('aci/attestation'), 1);
      h.clock.set(h.provider.session!.notAfter);
      await h.chat();
      expect(h.server.count('aci/attestation'), 2);
    });

    test('Kanal ohne Sitzung: fail-closed', () async {
      final channel = PhalaE2eeChannel(crypto: FakeAttestationCrypto());
      expect(channel.bound, isFalse);
      await expectLater(
        channel.begin(model: 'm'),
        throwsA(isA<AttestationFailedException>()),
      );
    });
  });

  group('Phala E2EE v2: Quittung', () {
    test('Request-Hash über den entschlüsselten Body, Response-Hash über die Chiffre-Bytes: grün', () async {
      final h = TeeHarness();
      await h.chat();
      final report = await h.provider.pendingReport();
      expect(report?.status, AttestationStatus.green);
      expect(h.lastRequest, h.lastExchange!.plainBytes);
      expect(utf8.decode(h.lastRequest!), contains('Geheimer Prompt-Text'));
      expect(utf8.decode(h.lastResponse!), isNot(contains('Hallo')));
    });

    test('Hash über den Wire-Body des Requests wäre rot', () async {
      final h = TeeHarness();
      // The gateway signs the plain body; a receipt over the cipher bytes
      // would not match.
      h.receiptEdit = (r) {
        for (final e
            in (r['event_log']! as List).cast<Map<String, Object?>>()) {
          if (e['type'] == 'request.received') {
            e['body_hash'] = sha256Of(
              Uint8List.fromList(
                utf8.encode(
                  h.server.requests
                      .firstWhere(
                        (x) => x.url.path.endsWith('chat/completions'),
                      )
                      .body,
                ),
              ),
            );
          }
        }
      };
      await h.chat();
      final report = await h.provider.pendingReport();
      expect(report?.status, AttestationStatus.red);
      expect(h.provider.locked, isTrue);
    });

    test('Hash über den Klartext der Antwort wäre rot', () async {
      final h = TeeHarness();
      h.receiptEdit = (r) {
        for (final e
            in (r['event_log']! as List).cast<Map<String, Object?>>()) {
          if (e['type'] == 'response.returned') {
            e['body_hash'] = sha256Of(
              Uint8List.fromList(utf8.encode(fixture('openai/text.sse'))),
            );
          }
        }
      };
      await h.chat();
      expect((await h.provider.pendingReport())?.status, AttestationStatus.red);
    });
  });
}
