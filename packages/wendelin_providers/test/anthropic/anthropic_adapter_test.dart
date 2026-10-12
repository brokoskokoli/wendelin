import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import '../support/sample_conversation.dart';

const _key = 'test-anthropic-key-0123456789';

AnthropicMessagesAdapter adapter(
  FakeServer server, {
  Uri? baseUrl,
  AnthropicOptions options = const AnthropicOptions(),
  HttpSettings settings = const HttpSettings(),
  Map<String, String> extraHeaders = const {},
}) => AnthropicMessagesAdapter(
  credentials: Credentials.apiKey(_key, style: ApiKeyStyle.xApiKey),
  defaultModel: 'claude-haiku-5-5',
  baseUrl: baseUrl,
  client: server.client,
  options: options,
  settings: settings,
  extraHeaders: extraHeaders,
);

Future<List<ChatEvent>> run(
  FakeServer server, {
  ChatRequest? request,
  AnthropicOptions options = const AnthropicOptions(),
}) async {
  final events = await adapter(
    server,
    options: options,
  ).chat(request ?? ContractExpectations.request()).toList();
  expectWellFormedChatStream(events);
  return events;
}

Usage sumUsage(List<ChatEvent> events) =>
    events.whereType<UsageEvent>().fold(Usage.zero, (sum, e) => sum + e.usage);

void main() {
  group('AnthropicMessagesAdapter – Fixtures', () {
    test(
      'Text: Deltas, Usage-Inkremente (kumulativ → Zuwachs), Done',
      () async {
        final events = await run(
          FakeServer([FakeResponse.sse(fixture('anthropic/text.sse'))]),
        );
        expect(events.whereType<TextDelta>().map((e) => e.text), [
          'Hallo! ',
          'Ich bin ',
          'Wendelin.',
        ]);
        expect(events.whereType<UsageEvent>().map((e) => e.usage), [
          const Usage(
            inputTokens: 25,
            outputTokens: 1,
            cachedInputTokens: 3000,
            cacheWriteTokens: 1200,
          ),
          const Usage(outputTokens: 11),
        ]);
        expect(
          sumUsage(events),
          const Usage(
            inputTokens: 25,
            outputTokens: 12,
            cachedInputTokens: 3000,
            cacheWriteTokens: 1200,
          ),
        );
        expect(events.last, const Done(StopReason.endTurn));
      },
    );

    test('Tool-Call: Argumente exakt aus zerstückelten Deltas', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('anthropic/tool_call.sse'))]),
      );
      expect(events.whereType<ToolCallDelta>().toList(), [
        const ToolCallDelta(
          index: 0,
          id: 'toolu_01EchoA',
          name: 'contract__echo',
        ),
        const ToolCallDelta(index: 0, argumentsFragment: '{"te'),
        const ToolCallDelta(index: 0, argumentsFragment: 'xt": "ha'),
        const ToolCallDelta(index: 0, argumentsFragment: 'llo"}'),
      ]);
      expect(
        events.whereType<ToolCallComplete>().single.call,
        const ToolCallBlock(
          id: 'toolu_01EchoA',
          name: 'contract__echo',
          argumentsJson: '{"text": "hallo"}',
        ),
      );
      expect(sumUsage(events), const Usage(inputTokens: 410, outputTokens: 38));
      expect(events.last, const Done(StopReason.toolUse));
    });

    test('parallele Tool-Calls: Ordnungszahlen statt Block-Index', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(fixture('anthropic/parallel_tool_calls.sse')),
        ]),
      );
      final calls = [
        for (final e in events.whereType<ToolCallComplete>()) e.call,
      ];
      expect(calls.map((c) => c.id), ['toolu_01Eins', 'toolu_01Zwei']);
      expect(calls.map((c) => c.argumentsJson), [
        '{"text": "eins"}',
        '{"text": "zwei"}',
      ]);
      expect(events.whereType<ToolCallDelta>().map((e) => e.index).toSet(), {
        0,
        1,
      });
      expect(
        events.whereType<TextDelta>().single.text,
        'Ich rufe zwei Tools auf.',
      );
    });

    test('Thinking mit Signatur und redacted Thinking', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('anthropic/thinking.sse'))]),
      );
      expect(
        events.whereType<ThinkingDelta>().map((e) => e.text).join(),
        'Der Nutzer will einen Termin.',
      );
      expect(events.whereType<ThinkingComplete>().map((e) => e.block), [
        const ThinkingBlock(
          'Der Nutzer will einen Termin.',
          signature: 'EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMOYds',
        ),
        const ThinkingBlock.redacted(
          'EmwKAhgBEgy3va3pzix/LafPsn4aDFIT2Xlxh0L5L8rLVyIwxtE3rAFBa8cr3qpP',
        ),
      ]);
      expect(events.whereType<TextDelta>().single.text, 'Erledigt.');
    });

    test('Web-Suche: Ergebnisse als Text, Server-Tool kein Tool-Call, '
        'pause_turn', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('anthropic/web_search.sse'))]),
      );
      expect(events.whereType<ToolCallDelta>(), isEmpty);
      expect(events.whereType<ToolCallComplete>(), isEmpty);
      final text = events.whereType<TextDelta>().map((e) => e.text).join();
      expect(
        text,
        '\n[Websuche „Wetter Berlin“: Wetter Berlin '
        '(https://wetter.example/berlin); DWD Berlin '
        '(https://dwd.example/berlin)]\n'
        'In Berlin sind es 18 Grad.',
      );
      expect(events.last, const Done(StopReason.pauseTurn));
    });

    test('Web-Suche: Fehler und leere Ergebnisse', () async {
      String sse(Object content) => [
        'event: message_start',
        'data: {"type":"message_start","message":{"usage":{"input_tokens":1}}}',
        '',
        'event: content_block_start',
        'data: ${jsonEncode({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'web_search_tool_result', 'tool_use_id': 'unbekannt', 'content': content},
        })}',
        '',
        'data: {"type":"content_block_stop","index":0}',
        '',
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
        '',
        'data: {"type":"message_stop"}',
        '',
        '',
      ].join('\n');
      final failed = await run(
        FakeServer([
          FakeResponse.sse(
            sse({
              'type': 'web_search_tool_result_error',
              'error_code': 'max_uses_exceeded',
            }),
          ),
        ]),
      );
      expect(
        failed.whereType<TextDelta>().single.text,
        '\n[Websuche fehlgeschlagen: max_uses_exceeded]\n',
      );
      final empty = await run(FakeServer([FakeResponse.sse(sse(<Object>[]))]));
      expect(
        empty.whereType<TextDelta>().single.text,
        '\n[Websuche: keine Ergebnisse]\n',
      );
    });

    test('Fehler-Event mitten im Tool-Call: ServerException 529', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(fixture('anthropic/error_during_tool_call.sse')),
        ]),
      );
      final error = (events.last as ErrorEvent).error;
      expect(error, isA<ServerException>());
      expect((error as ServerException).statusCode, 529);
      expect(error.message, contains('Overloaded'));
      expect(error.retryable, isTrue);
    });

    test('kaputte Zeile → MalformedResponseException', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('anthropic/broken_line.sse'))]),
      );
      expect(
        (events.last as ErrorEvent).error,
        isA<MalformedResponseException>(),
      );
      expect(events.whereType<Done>(), isEmpty);
    });

    test('Stream ohne message_stop → NetworkException', () async {
      final text = fixture('anthropic/text.sse');
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            text.substring(0, text.indexOf('event: message_stop')),
          ),
        ]),
      );
      expect((events.last as ErrorEvent).error, isA<NetworkException>());
    });

    for (final (name, body) in [
      ('message_stop ohne message_start', 'data: {"type":"message_stop"}\n\n'),
      (
        'Delta ohne Block',
        'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_delta","index":3,'
            '"delta":{"type":"text_delta","text":"x"}}\n\n',
      ),
      (
        'Stop ohne Block',
        'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_stop","index":3}\n\n',
      ),
      (
        'offener Tool-Block bei message_stop',
        'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_start","index":0,"content_block":'
            '{"type":"tool_use","id":"t","name":"n","input":{}}}\n\n'
            'data: {"type":"message_stop"}\n\n',
      ),
      (
        'tool_use ohne Namen',
        'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_start","index":0,"content_block":'
            '{"type":"tool_use","id":"t","input":{}}}\n\n',
      ),
      (
        'content_block fehlt',
        'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_start","index":0}\n\n',
      ),
      (
        'index fehlt',
        'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_stop"}\n\n',
      ),
      ('JSON-Array statt Objekt', 'data: [1,2]\n\n'),
    ]) {
      test('fehlerhafter Stream: $name → Malformed', () async {
        final events = await run(FakeServer([FakeResponse.sse(body)]));
        expect(
          (events.last as ErrorEvent).error,
          isA<MalformedResponseException>(),
        );
      });
    }

    test('unbekannte Events und Blocktypen werden ignoriert', () async {
      final events = await run(
        FakeServer([
          const FakeResponse.sse(
            'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"future_event"}\n\n'
            'data: {"type":"content_block_start","index":0,'
            '"content_block":{"type":"mcp_tool_use","id":"m"}}\n\n'
            'data: {"type":"content_block_delta","index":0,'
            '"delta":{"type":"input_json_delta","partial_json":"{}"}}\n\n'
            'data: {"type":"content_block_stop","index":0}\n\n'
            'data: {"type":"content_block_start","index":1,'
            '"content_block":{"type":"text","text":"Start"}}\n\n'
            'data: {"type":"content_block_stop","index":1}\n\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"refusal"}}\n\n'
            'data: {"type":"message_stop"}\n\n',
          ),
        ]),
      );
      expect(events, [
        const TextDelta('Start'),
        const Done(StopReason.refusal),
      ]);
    });

    test('Tool ohne Argument-Deltas → "{}"', () async {
      final events = await run(
        FakeServer([
          const FakeResponse.sse(
            'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"content_block_start","index":0,"content_block":'
            '{"type":"tool_use","id":"t","name":"n","input":{}}}\n\n'
            'data: {"type":"content_block_stop","index":0}\n\n'
            'data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}\n\n'
            'data: {"type":"message_stop"}\n\n',
          ),
        ]),
      );
      expect(
        events.whereType<ToolCallComplete>().single.call.argumentsJson,
        '{}',
      );
    });

    test('Stop-Reasons', () async {
      for (final (wire, expected) in [
        ('end_turn', StopReason.endTurn),
        ('tool_use', StopReason.toolUse),
        ('max_tokens', StopReason.maxTokens),
        ('model_context_window_exceeded', StopReason.maxTokens),
        ('stop_sequence', StopReason.stopSequence),
        ('pause_turn', StopReason.pauseTurn),
        ('refusal', StopReason.refusal),
        ('etwas_neues', StopReason.other),
      ]) {
        final events = await run(
          FakeServer([
            FakeResponse.sse(
              'data: {"type":"message_start","message":{}}\n\n'
              'data: {"type":"message_delta","delta":{"stop_reason":"$wire"}}\n\n'
              'data: {"type":"message_stop"}\n\n',
            ),
          ]),
        );
        expect(events.last, Done(expected), reason: wire);
      }
      final noReason = await run(
        FakeServer([
          const FakeResponse.sse(
            'data: {"type":"message_start","message":{}}\n\n'
            'data: {"type":"message_stop"}\n\n',
          ),
        ]),
      );
      expect(noReason.last, const Done(StopReason.other));
    });
  });

  group('AnthropicMessagesAdapter – HTTP', () {
    test('Request: URL, Header, Body', () async {
      final server = FakeServer([
        FakeResponse.sse(fixture('anthropic/text.sse')),
      ]);
      await adapter(
        server,
        extraHeaders: {'x-extra': '1'},
      ).chat(sampleRequest()).toList();
      final r = server.requests.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(r.headers['x-api-key'], _key);
      expect(r.headers['anthropic-version'], '2023-06-01');
      expect(r.headers['x-extra'], '1');
      expect(r.headers['content-type'], startsWith('application/json'));
      expect(r.json['stream'], isTrue);
      expect(r.json['model'], 'test-model');
    });

    test('Base-URL mit und ohne /v1 und Schrägstrich', () async {
      for (final base in [
        'https://proxy.example',
        'https://proxy.example/',
        'https://proxy.example/v1',
        'https://proxy.example/v1/',
      ]) {
        final server = FakeServer([
          FakeResponse.sse(fixture('anthropic/text.sse')),
        ]);
        await adapter(
          server,
          baseUrl: Uri.parse(base),
        ).chat(sampleRequest()).toList();
        expect(
          server.requests.single.url.toString(),
          'https://proxy.example/v1/messages',
          reason: base,
        );
      }
    });

    for (final (status, file, type, retryable) in [
      (400, '400.json', InvalidRequestException, false),
      (401, '401.json', AuthException, false),
      (403, '401.json', AuthException, false),
      (404, '400.json', InvalidRequestException, false),
      (408, '529.json', ProviderTimeoutException, true),
      (429, '429.json', RateLimitException, true),
      (500, '529.json', ServerException, true),
      (504, '529.json', ProviderTimeoutException, true),
      (529, '529.json', ServerException, true),
    ]) {
      test('HTTP $status → $type', () async {
        final events = await run(
          FakeServer([FakeResponse.json(status, fixture('anthropic/$file'))]),
        );
        final error = (events.single as ErrorEvent).error;
        expect(error.runtimeType, type);
        expect(error.retryable, retryable);
        expect(error.message, contains('HTTP $status'));
      });
    }

    test('429 mit retry-after', () async {
      final events = await run(
        FakeServer([
          FakeResponse.json(
            429,
            fixture('anthropic/429.json'),
            headers: {'retry-after': '20'},
          ),
        ]),
      );
      final error = (events.single as ErrorEvent).error as RateLimitException;
      expect(error.retryAfter, const Duration(seconds: 20));
      expect(error.message, contains('rate limit'));
    });

    test('Abbruch schließt die HTTP-Verbindung', () async {
      final server = FakeServer([
        const FakeResponse.hang(
          'data: {"type":"message_start","message":{}}\n\n'
          'data: {"type":"content_block_start","index":0,'
          '"content_block":{"type":"text","text":"x"}}\n\n',
        ),
      ]);
      final cancel = CancelToken();
      final events = <ChatEvent>[];
      await for (final e in adapter(
        server,
      ).chat(sampleRequest(), cancel: cancel)) {
        events.add(e);
        if (e is TextDelta) cancel.cancel();
      }
      expect((events.last as ErrorEvent).error, isA<CancelledException>());
      await pumpEventQueue();
      expect(server.bodyCancelled, isTrue);
      expect(server.aborted, isTrue);
    });

    test('Abbruch bevor die Antwort-Header kommen', () async {
      final server = FakeServer([const FakeResponse.never()]);
      final cancel = CancelToken();
      final future = adapter(server)
          .chat(sampleRequest(), cancel: cancel)
          .toList();
      await pumpEventQueue();
      cancel.cancel();
      final events = await future;
      expect(events, [const ErrorEvent(CancelledException())]);
      expect(server.aborted, isTrue);
    });

    test('Konsument bricht das Abo ab: Verbindung wird geschlossen', () async {
      final server = FakeServer([
        const FakeResponse.hang(
          'data: {"type":"message_start","message":{}}\n\n'
          'data: {"type":"content_block_start","index":0,'
          '"content_block":{"type":"text","text":"x"}}\n\n',
        ),
      ]);
      final first = await adapter(server).chat(sampleRequest()).first;
      expect(first, const TextDelta('x'));
      await pumpEventQueue();
      expect(server.bodyCancelled, isTrue);
      expect(server.aborted, isTrue);
    });

    test('Zeitüberschreitung beim Warten auf Header', () async {
      final server = FakeServer([const FakeResponse.never()]);
      final events = await adapter(
        server,
        settings: const HttpSettings(
          responseTimeout: Duration(milliseconds: 20),
        ),
      ).chat(sampleRequest()).toList();
      expect(
        (events.single as ErrorEvent).error,
        isA<ProviderTimeoutException>(),
      );
      expect(server.aborted, isTrue);
    });

    test('Zeitüberschreitung bei Funkstille im Stream', () async {
      final server = FakeServer([
        const FakeResponse.hang(
          'data: {"type":"message_start","message":{}}\n\n',
        ),
      ]);
      final events = await adapter(
        server,
        settings: const HttpSettings(idleTimeout: Duration(milliseconds: 20)),
      ).chat(sampleRequest()).toList();
      expect(
        (events.last as ErrorEvent).error,
        isA<ProviderTimeoutException>(),
      );
      expect(server.aborted, isTrue);
    });

    test('Netzwerkfehler → NetworkException', () async {
      final events = await run(
        FakeServer([
          FakeResponse.fail(http.ClientException('Connection refused')),
        ]),
      );
      final error = (events.single as ErrorEvent).error;
      expect(error, isA<NetworkException>());
      expect(error.message, contains('Connection refused'));
    });

    test('fehlender Key → AuthException ohne Request', () async {
      final server = FakeServer([]);
      final events = await AnthropicMessagesAdapter(
        credentials: Credentials(
          const ApiKeyAuth('anthropic'),
          (_) async => null,
          style: ApiKeyStyle.xApiKey,
        ),
        defaultModel: 'm',
        client: server.client,
      ).chat(sampleRequest()).toList();
      expect((events.single as ErrorEvent).error, isA<AuthException>());
      expect(server.requests, isEmpty);
    });

    test('Log enthält Methode, URL und Status, aber keine Header', () async {
      final lines = <String>[];
      final server = FakeServer([
        FakeResponse.json(401, fixture('anthropic/401.json')),
      ]);
      await adapter(
        server,
        settings: HttpSettings(log: lines.add),
      ).chat(sampleRequest()).toList();
      expect(
        lines.join('\n'),
        contains('POST https://api.anthropic.com/v1/messages'),
      );
      expect(lines.join('\n'), contains('HTTP 401'));
      expect(lines.join('\n'), isNot(contains(_key)));
      expect(lines.join('\n'), isNot(contains('anthropic-version')));
    });

    test('caps und type', () {
      final a = adapter(FakeServer([]));
      expect(a.type, ProviderType.anthropic);
      expect(a.caps.promptCaching, isTrue);
      expect(a.caps.tools, isTrue);
      expect(a.toString(), isNot(contains(_key)));
    });
  });

  group('AnthropicMessagesAdapter – listModels und test()', () {
    test('listModels liest Modelle mit Kontext und Vision', () async {
      final server = FakeServer([
        FakeResponse.json(200, fixture('anthropic/models.json')),
      ]);
      final models = await adapter(server).listModels();
      expect(models, [
        const ModelInfo(
          id: 'claude-haiku-5-5',
          displayName: 'Claude Haiku 5.5',
          contextWindow: 1000000,
          supportsTools: true,
          supportsVision: true,
        ),
        const ModelInfo(
          id: 'claude-sonnet-5-5',
          displayName: 'Claude Sonnet 5.5',
          contextWindow: 1000000,
          supportsTools: true,
          supportsVision: true,
        ),
      ]);
      expect(
        server.requests.single.url.toString(),
        'https://api.anthropic.com/v1/models?limit=1000',
      );
      expect(server.requests.single.headers['x-api-key'], _key);
    });

    test('listModels blättert über has_more/last_id', () async {
      final server = FakeServer([
        const FakeResponse.json(
          200,
          '{"data":[{"id":"a"}],"has_more":true,"last_id":"a"}',
        ),
        const FakeResponse.json(
          200,
          '{"data":[{"id":"b"},{"x":1}],"has_more":false,"last_id":"b"}',
        ),
      ]);
      final models = await adapter(server).listModels();
      expect(models.map((m) => m.id), ['a', 'b']);
      expect(server.requests[1].url.queryParameters['after_id'], 'a');
    });

    test(
      'listModels: 401 → AuthException, kaputtes JSON → Malformed',
      () async {
        await expectLater(
          adapter(
            FakeServer([FakeResponse.json(401, fixture('anthropic/401.json'))]),
          ).listModels(),
          throwsA(isA<AuthException>()),
        );
        await expectLater(
          adapter(FakeServer([const FakeResponse.json(200, '[1]')]))
              .listModels(),
          throwsA(isA<MalformedResponseException>()),
        );
        await expectLater(
          adapter(FakeServer([const FakeResponse.json(200, '{kaputt')]))
              .listModels(),
          throwsA(isA<MalformedResponseException>()),
        );
      },
    );

    test('test(): Modelle und Tool-Aufruf erkannt', () async {
      final clock = FixedClock(DateTime.utc(2026, 10, 13));
      final server = FakeServer([
        FakeResponse.json(200, fixture('anthropic/models.json')),
        FakeResponse.sse(
          fixture('anthropic/tool_call.sse')
              .replaceAll('contract__echo', 'wendelin__ping'),
        ),
      ]);
      final health = await adapter(
        server,
        settings: HttpSettings(clock: clock),
      ).test();
      expect(health.ok, isTrue);
      expect(health.models, hasLength(2));
      expect(health.detected?.tools, isTrue);
      expect(health.detected?.promptCaching, isTrue);
      expect(health.message, contains('Tool-Aufruf funktioniert'));
      final probe = server.requests[1].json;
      expect(probe['model'], 'claude-haiku-5-5');
      expect(
        (probe['tools']! as List).single,
        containsPair('name', 'wendelin__ping'),
      );
    });

    test(
      'test(): Antwort ohne Tool-Aufruf → ok, tools nicht erkannt',
      () async {
        final health = await adapter(
          FakeServer([
            FakeResponse.json(200, fixture('anthropic/models.json')),
            FakeResponse.sse(fixture('anthropic/text.sse')),
          ]),
        ).test();
        expect(health.ok, isTrue);
        expect(health.detected?.tools, isFalse);
        expect(health.message, contains('kein Tool'));
      },
    );

    test('test(): ungültiger Key → ok false, keine Exception', () async {
      final health = await adapter(
        FakeServer([FakeResponse.json(401, fixture('anthropic/401.json'))]),
      ).test();
      expect(health.ok, isFalse);
      expect(health.message, contains('401'));
    });

    test('test(): Modellliste fehlt, Chat scheitert → ok false', () async {
      final health = await adapter(
        FakeServer([
          const FakeResponse.json(404, '{}'),
          FakeResponse.json(529, fixture('anthropic/529.json')),
        ]),
      ).test();
      expect(health.ok, isFalse);
      expect(health.models, isNull);
      expect(health.message, contains('529'));
    });
  });
}
