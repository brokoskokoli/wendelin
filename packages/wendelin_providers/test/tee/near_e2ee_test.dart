import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import 'near_support.dart';
import 'tee_support.dart';

/// [NearCrypto] whose client identity is fixed, so the recorded answers of
/// the live service can be opened.
final class FixedIdentityCrypto implements NearCrypto {
  FixedIdentityCrypto(this._seed);
  final Uint8List _seed;
  final _ref = NearReferenceCrypto();

  @override
  NearIdentity nearGenerateIdentity() =>
      NearReferenceCrypto.identityFromSeed(_seed);
  @override
  String nearEncrypt(Uint8List r, Uint8List p) => _ref.nearEncrypt(r, p);
  @override
  Uint8List nearDecrypt(Uint8List s, String w) => _ref.nearDecrypt(s, w);
}

final _modelKey = E2eeKey(
  keyId: 'model',
  algo: 'ed25519',
  publicKey: AttestCodec.unhex(
    '5a0210f2442c79355784f9de021985429561da5bacc3a4424b01ac52b7e0caff',
  ),
);

List<SseEvent> sseEvents(String body) => [
  for (final block in body.split('\n\n'))
    if (block.startsWith('data: ')) SseEvent(data: block.substring(6)),
];

Matcher failsAt(String stage) => throwsA(
  isA<AttestationFailedException>().having((e) => e.stage, 'stage', stage),
);

ToolSpec timerTool() => const ToolSpec(
  name: 'timer__set',
  description: 'Stellt einen geheimen Timer',
  inputSchema: {
    'type': 'object',
    'properties': {
      'minutes': {'type': 'integer', 'description': 'Minuten bis Nudeln'},
    },
  },
);

void main() {
  group('NearE2eeWire gegen die aufgezeichnete Antwort des Dienstes', () {
    final ex = nearExchange();
    final seed = AttestCodec.unhex(ex['client_seed_hex']! as String);
    NearE2eeWire wire() =>
        NearE2eeWire(crypto: FixedIdentityCrypto(seed), key: _modelKey);

    test('Streaming: Werkzeugaufruf und Denken werden geöffnet', () {
      final w = wire();
      final stream = ex['stream']! as Map<String, Object?>;
      final names = StringBuffer();
      final args = StringBuffer();
      var reasoning = '';
      for (final e in sseEvents(stream['response_body']! as String)) {
        if (e.isDone) continue;
        final json = jsonDecode(w.open(e).data) as Map<String, Object?>;
        for (final c in (json['choices'] as List<Object?>)) {
          final delta =
              (c! as Map<String, Object?>)['delta'] as Map<String, Object?>?;
          reasoning += (delta?['reasoning_content'] as String?) ?? '';
          for (final t
              in (delta?['tool_calls'] as List<Object?>? ?? const [])) {
            final f =
                (t! as Map<String, Object?>)['function']!
                    as Map<String, Object?>;
            names.write(f['name'] ?? '');
            args.write(f['arguments'] ?? '');
          }
        }
      }
      expect(names.toString(), 'timer_set');
      expect(jsonDecode(args.toString()), {'minutes': 12});
      expect(reasoning, isNotEmpty);
    }, skip: false);

    test('ohne Streaming: message.tool_calls', () {
      final plain = ex['plain']! as Map<String, Object?>;
      final out = jsonDecode(
        wire().openJson(plain['response_body']! as String),
      ) as Map<String, Object?>;
      final msg =
          ((out['choices']! as List<Object?>).first!
                  as Map<String, Object?>)['message']!
              as Map<String, Object?>;
      final call =
          ((msg['tool_calls']! as List<Object?>).first!
                  as Map<String, Object?>)['function']!
              as Map<String, Object?>;
      expect(call['name'], 'timer_set');
      expect(jsonDecode(call['arguments']! as String), {'minutes': 12});
    });

    test('ein falscher Client-Schlüssel öffnet nichts', () {
      final w = NearE2eeWire(crypto: NearReferenceCrypto(), key: _modelKey);
      final events = sseEvents(
        (ex['stream']! as Map)['response_body']! as String,
      );
      expect(() => events.map(w.open).toList(), failsAt('e2ee.response'));
    });

    test(
      'Klartext, wiederholtes Stück, wechselnde Id und kaputtes Hex scheitern',
      () {
        final bodies = (ex['stream']! as Map)['response_body']! as String;
        final events = sseEvents(bodies);
        // Klartext in einem verschlüsselten Feld
        final plain = SseEvent(
          data: '{"id":"x","choices":[{"index":0,"delta":{"content":"Hallo im Klartext"}}]}',
        );
        expect(() => wire().open(plain), failsAt('e2ee.response'));
        // Tool-Aufruf im Klartext (Downgrade der Werkzeugfelder)
        final plainTool = SseEvent(
          data: '{"id":"x","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"name":"timer_set","arguments":"{}"}}]}}]}',
        );
        expect(() => wire().open(plainTool), failsAt('e2ee.response'));
        // dasselbe Stück zweimal (Wiederholung durch das Gateway)
        final w = wire();
        final withReasoning = events.firstWhere(
          (e) => e.data.contains('reasoning_content":"'),
        );
        w.open(withReasoning);
        expect(() => w.open(withReasoning), failsAt('e2ee.response'));
        // andere Antwort-Kennung mitten im Strom
        final w2 = wire();
        w2.open(withReasoning);
        final other = SseEvent(
          data: withReasoning.data.replaceFirst(
            RegExp(r'"id":"[0-9a-f]+"'),
            '"id":"fremd"',
          ),
        );
        expect(() => w2.open(other), failsAt('e2ee.response'));
        // kaputtes Hex
        final broken = SseEvent(
          data: withReasoning.data.replaceFirst(
            RegExp(r'reasoning_content":"[0-9a-f]{4}'),
            'reasoning_content":"zzzz',
          ),
        );
        expect(() => wire().open(broken), failsAt('e2ee.response'));
        // Beschädigtes Chiffrat
        final flipped = SseEvent(
          data: withReasoning.data.replaceFirstMapped(
            RegExp(r'(reasoning_content":"[0-9a-f]{100})([0-9a-f])'),
            (m) => '${m[1]}${m[2] == '0' ? '1' : '0'}',
          ),
        );
        expect(flipped.data, isNot(withReasoning.data));
        expect(() => wire().open(flipped), failsAt('e2ee.response'));
      },
    );

    test('Fehlerobjekt im Klartext, Nutzungsstück und [DONE] gehen durch', () {
      final w = wire();
      final usage = SseEvent(
        data: '{"id":"x","choices":[],"usage":{"total_tokens":3}}',
      );
      expect(identical(w.open(usage), usage), isTrue);
      final error = SseEvent(data: '{"error":{"message":"kaputt"}}');
      expect(w.open(error).data, contains('kaputt'));
      const done = SseEvent(data: '[DONE]');
      expect(w.open(done), done);
      // choices neben error werden nie durchgereicht
      final mixed = SseEvent(
        data: '{"error":{"message":"x"},"choices":[{"delta":{"content":"geheim"}}]}',
      );
      expect(w.open(mixed).data, isNot(contains('geheim')));
    });
  });

  group('NearE2eeWire: Anfrage', () {
    final service = FakeNearService();
    NearE2eeWire wire() => NearE2eeWire(
      crypto: NearReferenceCrypto(),
      key: E2eeKey(
        keyId: 'm',
        algo: 'ed25519',
        publicKey: service.identity.public,
      ),
    );

    Map<String, Object?> body() => {
      'model': nearModel,
      'messages': [
        {'role': 'system', 'content': 'Geheimer Systemtext'},
        {'role': 'user', 'content': 'Geheimer Nutzertext'},
        {'role': 'user', 'content': '[1,2,3]'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'kalender__loeschen',
                'arguments': '{"titel":"Geheimtermin"}',
              },
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': 'Ergebnis Geheimtermin gelöscht',
        },
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Teil Eins'},
          ],
        },
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'timer__set',
            'description': 'Stellt einen geheimen Timer',
            'parameters': {
              'type': 'object',
              'properties': {
                'minutes': {'type': 'integer'},
              },
            },
          },
        },
      ],
      'tool_choice': {
        'type': 'function',
        'function': {'name': 'timer__set'},
      },
      'max_tokens': 50,
      'temperature': 0.2,
      'stream': true,
      'stream_options': {'include_usage': true},
    };

    test('kein Klartext im Wire, auch nicht bei Werkzeugen', () {
      final w = wire();
      final sealed = w.seal(body());
      for (final secret in [
        'Geheimer Systemtext',
        'Geheimer Nutzertext',
        'kalender__loeschen',
        'Geheimtermin',
        'timer__set',
        'geheimen Timer',
        'minutes',
        'Teil Eins',
        'Ergebnis',
      ]) {
        expect(sealed.wire, isNot(contains(secret)), reason: secret);
      }
      // sichtbar bleiben nur Routing-Felder
      expect(sealed.wire, contains('"model":"$nearModel"'));
      expect(sealed.wire, contains('call_1'));
      expect(
        utf8.decode(sealed.plain),
        sealed.wire,
        reason: 'Quittung gilt den Wire-Bytes',
      );
    });

    test('der Dienst stellt die Anfrage genau wieder her', () {
      final w = wire();
      final sealed = w.seal(body());
      final exchange = service.open(
        w.headers,
        Uint8List.fromList(utf8.encode(sealed.wire)),
      );
      final r = exchange.request;
      final messages = r['messages']! as List<Object?>;
      expect((messages[0]! as Map)['content'], 'Geheimer Systemtext');
      // wie ein JSON-Array aussehender Text bleibt Text
      expect((messages[2]! as Map)['content'], [
        {'type': 'text', 'text': '[1,2,3]'},
      ]);
      expect(
        (messages[5]! as Map)['content'],
        ((body()['messages']! as List)[5] as Map)['content'],
      );
      final call = ((messages[3]! as Map)['tool_calls']! as List).first as Map;
      expect(call['function'], {
        'name': 'kalender__loeschen',
        'arguments': '{"titel":"Geheimtermin"}',
      });
      expect(r['tools'], body()['tools']);
      expect(r['tool_choice'], body()['tool_choice']);
      expect(r['max_tokens'], 50);
    });

    test(
      'Header: Ed25519-Schlüssel, Version 2, alle Felder, kein Aliasing',
      () {
        final h = wire().headers;
        expect(h['X-Signing-Algo'], 'ed25519');
        expect(h['X-Encryption-Version'], '2');
        expect(h['X-Encrypt-All-Fields'], 'true');
        expect(h['x-no-aliasing'], 'true');
        expect(h['X-Model-Pub-Key'], service.publicKeyHex);
        expect(h['X-Client-Pub-Key'], hasLength(64));
        expect(
          wire().headers['X-Client-Pub-Key'],
          isNot(h['X-Client-Pub-Key']),
        );
      },
    );

    test('unbekannte Felder und kaputte Anfragen werden nicht gesendet', () {
      for (final bad in [
        {
          ...body(),
          'response_format': {'type': 'json_object'},
        },
        {
          ...body(),
          'stop': ['geheim'],
        },
        {...body(), 'messages': <Object?>[]},
        {
          ...body(),
          'tools': [
            {'type': 'web_search'},
          ],
        },
        {
          ...body(),
          'messages': [
            {'role': 'user', 'content': 5},
          ],
        },
      ]) {
        expect(() => wire().seal(bad), failsAt('e2ee.request'));
      }
    });

    test('der strenge Fake-Dienst weist unverschlüsselte Felder zurück', () {
      final w = wire();
      final sealed = jsonDecode(w.seal(body()).wire) as Map<String, Object?>;
      (sealed['tools']! as List).first['function']['parameters'] = {
        'type': 'object',
      };
      expect(
        () => service.open(
          w.headers,
          Uint8List.fromList(utf8.encode(jsonEncode(sealed))),
        ),
        throwsA(isA<NearRejection>()),
      );
    });
  });

  group('AttestedProvider mit NEAR', () {
    late FakeNearService service;
    late TeeServer server;
    late AttestedProvider provider;
    late FixedClock clock;
    late InMemoryAttestationLog log;
    Uint8List? lastRequest;
    Uint8List? lastResponse;
    NearExchange? lastExchange;
    var chatCalls = 0;
    var tamperHash = false;
    String Function(NearExchange, String)? seal;
    String plainFixture = 'openai/tool_call.sse';
    final crypto = FakeAttestationCrypto(ed25519Result: true);

    setUp(() {
      service = FakeNearService();
      log = InMemoryAttestationLog();
      clock = FixedClock(probeNow);
      chatCalls = 0;
      tamperHash = false;
      seal = null;
      plainFixture = 'openai/tool_call.sse';
      server = TeeServer({
        'attestation/report': (_) => http.Response(
          jsonEncode(nearReportFor(service.publicKeyHex)),
          200,
          headers: {'content-type': 'application/json'},
        ),
        'signature/': (_) {
          String h(Uint8List b) => AttestCodec.hex(crypto.sha256(b));
          return http.Response(
            jsonEncode({
              'text':
                  '$nearModel:${h(lastRequest!)}:${h(tamperHash ? Uint8List.fromList([...lastResponse!, 10]) : lastResponse!)}',
              'signature': '00' * 64,
              'signing_address': service.publicKeyHex,
              'signing_algo': 'ed25519',
              'signature_kind': 'provider_tee',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
        'chat/completions': (request) {
          chatCalls++;
          final NearExchange exchange;
          try {
            exchange = service.open(request.headers, request.bodyBytes);
          } on NearRejection catch (e) {
            return http.Response(e.body, 400);
          }
          lastExchange = exchange;
          lastRequest = request.bodyBytes;
          final plain = fixture(plainFixture);
          lastResponse = Uint8List.fromList(
            utf8.encode(seal?.call(exchange, plain) ?? exchange.sealSse(plain)),
          );
          return http.Response.bytes(
            lastResponse!,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        },
      });
      final settings = HttpSettings(clock: clock);
      final verifier = NearVerifier(
        crypto: crypto,
        baseUrl: Uri.parse('https://cloud-api.test/v1'),
        model: nearModel,
        profileId: 'near',
        headers: () async => {'authorization': 'Bearer test'},
        client: server.client,
        settings: settings,
        nonceSource: () => nearNonce,
      );
      provider = AttestedProvider(
        inner: OpenAiChatAdapter(
          baseUrl: Uri.parse('https://cloud-api.test/v1'),
          credentials: Credentials.apiKey('test', style: ApiKeyStyle.bearer),
          defaultModel: nearModel,
          client: server.client,
          settings: settings,
          wireCodec: NearE2eeChannel(crypto: NearReferenceCrypto()),
        ),
        verifier: verifier,
        profileId: 'near',
        logSink: log,
        settings: settings,
        retryDelay: Duration.zero,
        requireUpstreamEnforced: false,
      );
    });

    ChatRequest request({String? model}) => ChatRequest(
      systemPrompt: 'Systemtext',
      messages: [Message.user('Geheimer Nutzertext')],
      tools: [timerTool()],
      model: model ?? nearModel,
      maxTokens: 50,
    );

    test(
      'Streaming mit Werkzeugaufruf: entschlüsselt, Quittung grün',
      () async {
        final events = await provider.chat(request()).toList();
        expect(events.whereType<ErrorEvent>(), isEmpty);
        final call = events.whereType<ToolCallComplete>().single.call;
        expect(call.name, 'contract__echo');
        expect(call.id, 'call_EchoA');
        expect(jsonDecode(call.argumentsJson), isA<Map>());
        final wire = utf8.decode(lastRequest!);
        for (final secret in [
          'Geheimer Nutzertext',
          'timer__set',
          'geheimen Timer',
        ]) {
          expect(wire, isNot(contains(secret)));
        }
        expect(lastExchange!.request['tools'], isNotEmpty);
        final report = await provider.pendingReport();
        expect(
          report!.status,
          AttestationStatus.green,
          reason: '${report.detail}',
        );
        expect(provider.session!.workloadId, nearModel);
        expect(
          log.entries.map((e) => e.kind),
          contains(AttestationLogKind.receipt),
        );
        expect(
          server.requests
              .where((r) => r.url.path.contains('signature/'))
              .single
              .url
              .queryParameters,
          {'model': nearModel, 'signing_algo': 'ed25519'},
        );
      },
    );

    test('Quittung mit anderem Hash sperrt den Anbieter', () async {
      tamperHash = true;
      await provider.chat(request()).toList();
      final report = await provider.pendingReport();
      expect(report!.status, AttestationStatus.red);
      expect(provider.locked, isTrue);
    });

    test('Klartext-Antwort wird verworfen und erzwingt neue Prüfung', () async {
      seal = (x, plain) => plain;
      final events = await provider.chat(request()).toList();
      final error = events.whereType<ErrorEvent>().single.error;
      expect(error, isA<AttestationFailedException>());
      expect((error as AttestationFailedException).stage, startsWith('e2ee.'));
      expect(events.whereType<ToolCallComplete>(), isEmpty);
      expect(
        provider.session,
        isNull,
        reason: 'nächste Anfrage attestiert neu',
      );
    });

    test('anderes Modell als geprüft: Anfrage wird nicht gesendet', () async {
      final events = await provider
          .chat(request(model: 'Qwen/Qwen3.8-27B'))
          .toList();
      expect(
        events.whereType<ErrorEvent>().single.error,
        isA<AttestationFailedException>(),
      );
      expect(chatCalls, 0);
    });

    test('Attestierung rot: nichts wird gesendet', () async {
      final doc = nearReportFor(service.publicKeyHex);
      editModel(
        doc,
        (m) => m['signing_public_key'] = flipHex(
          m['signing_public_key']! as String,
          3,
        ),
      );
      server.routes['attestation/report'] = jsonBody(doc);
      final events = await provider.chat(request()).toList();
      expect(
        events.whereType<ErrorEvent>().single.error,
        isA<AttestationFailedException>(),
      );
      expect(chatCalls, 0);
      expect(provider.locked, isTrue);
    });

    test('der Kanal bindet nur einmal', () {
      final channel = NearE2eeChannel(crypto: NearReferenceCrypto());
      channel.bind(() => null, clock);
      expect(() => channel.bind(() => null, clock), throwsStateError);
    });
  });
}
