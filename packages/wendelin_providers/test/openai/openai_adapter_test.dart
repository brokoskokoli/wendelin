import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import '../support/sample_conversation.dart';

const _key = 'test-openai-key-0123456789';

OpenAiChatAdapter adapter(
  FakeServer server, {
  String baseUrl = 'https://api.openai.com/v1',
  OpenAiOptions options = const OpenAiOptions(),
  Credentials? credentials,
  HttpSettings settings = const HttpSettings(),
}) => OpenAiChatAdapter(
  baseUrl: Uri.parse(baseUrl),
  credentials:
      credentials ?? Credentials.apiKey(_key, style: ApiKeyStyle.bearer),
  defaultModel: 'gpt-4.1-nano',
  label: 'OpenAI',
  client: server.client,
  options: options,
  settings: settings,
);

Future<List<ChatEvent>> run(
  FakeServer server, {
  OpenAiOptions options = const OpenAiOptions(),
}) async {
  final events = await adapter(
    server,
    options: options,
  ).chat(ContractExpectations.request()).toList();
  expectWellFormedChatStream(events);
  return events;
}

String chunk(Map<String, Object?> delta, {String? finish}) =>
    'data: {"choices":[{"index":0,"delta":${_json(delta)},'
    '"finish_reason":${finish == null ? 'null' : '"$finish"'}}]}\n\n';

String _json(Object? o) => switch (o) {
  final Map<String, Object?> m =>
    '{${m.entries.map((e) => '"${e.key}":${_json(e.value)}').join(',')}}',
  final List<Object?> l => '[${l.map(_json).join(',')}]',
  final String s => '"${s.replaceAll('"', r'\"')}"',
  null => 'null',
  _ => '$o',
};

void main() {
  // WP120: the first text reaches the consumer while the stream is still
  // open (the voice output starts with it).
  test('erstes Textstück kommt, bevor der Strom endet (Streaming)', () async {
    final server = FakeServer([
      FakeResponse.hang(chunk({'role': 'assistant', 'content': 'Hallo'})),
    ]);
    final first = await adapter(server)
        .chat(ContractExpectations.request())
        .first;
    expect(first, const TextDelta('Hallo'));
  });

  group('OpenAiChatAdapter – Fixtures', () {
    test('Text mit Usage aus letztem Chunk (Cache-Anteil getrennt)', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('openai/text.sse'))]),
      );
      expect(events, [
        const TextDelta('Hallo! '),
        const TextDelta('Ich bin Wendelin.'),
        const UsageEvent(
          Usage(inputTokens: 226, outputTokens: 9, cachedInputTokens: 1024),
        ),
        const Done(StopReason.endTurn),
      ]);
    });

    test('Tool-Call: Argumente exakt aus Deltas', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('openai/tool_call.sse'))]),
      );
      expect(events.whereType<ToolCallDelta>().toList(), [
        const ToolCallDelta(index: 0, id: 'call_EchoA', name: 'contract__echo'),
        const ToolCallDelta(index: 0, argumentsFragment: '{"te'),
        const ToolCallDelta(index: 0, argumentsFragment: 'xt":"ha'),
        const ToolCallDelta(index: 0, argumentsFragment: 'llo"}'),
      ]);
      expect(
        events.whereType<ToolCallComplete>().single.call,
        const ToolCallBlock(
          id: 'call_EchoA',
          name: 'contract__echo',
          argumentsJson: '{"text":"hallo"}',
        ),
      );
      expect(events.last, const Done(StopReason.toolUse));
    });

    test('parallele Tool-Calls mit verschachtelten Fragmenten', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(fixture('openai/parallel_tool_calls.sse')),
        ]),
      );
      final calls = [
        for (final e in events.whereType<ToolCallComplete>()) e.call,
      ];
      expect(calls, [
        const ToolCallBlock(
          id: 'call_Eins',
          name: 'contract__echo',
          argumentsJson: '{"text":"eins"}',
        ),
        const ToolCallBlock(
          id: 'call_Zwei',
          name: 'contract__echo',
          argumentsJson: '{"text":"zwei"}',
        ),
      ]);
      final completeAt = events.indexWhere((e) => e is ToolCallComplete);
      final usageAt = events.indexWhere((e) => e is UsageEvent);
      expect(completeAt, lessThan(usageAt));
    });

    test(
      'Reasoning-Deltas werden Thinking, abgeschlossen vor dem Text',
      () async {
        final events = await run(
          FakeServer([FakeResponse.sse(fixture('openai/reasoning.sse'))]),
        );
        expect(events, [
          const ThinkingDelta('Der Nutzer '),
          const ThinkingDelta('grüßt.'),
          const ThinkingComplete(ThinkingBlock('Der Nutzer grüßt.')),
          const TextDelta('Hallo!'),
          const UsageEvent(Usage(inputTokens: 17, outputTokens: 30)),
          const Done(StopReason.endTurn),
        ]);
      },
    );

    test('emitReasoning: false verwirft Reasoning', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('openai/reasoning.sse'))]),
        options: const OpenAiOptions(emitReasoning: false),
      );
      expect(events.whereType<ThinkingDelta>(), isEmpty);
      expect(events.whereType<ThinkingComplete>(), isEmpty);
      expect(events.whereType<TextDelta>().single.text, 'Hallo!');
    });

    test('Feld "reasoning" (OpenRouter) und Reasoning bis zum Ende', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({'reasoning': 'hm'})}${chunk({}, finish: 'length')}'
            'data: [DONE]\n\n',
          ),
        ]),
      );
      expect(events, [
        const ThinkingDelta('hm'),
        const ThinkingComplete(ThinkingBlock('hm')),
        const Done(StopReason.maxTokens),
      ]);
    });

    test('Reasoning vor Tool-Call wird vorher abgeschlossen', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({'reasoning_content': 'plane'})}'
            '${chunk({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'c1',
                  'function': {'name': 'n', 'arguments': '{}'},
                },
              ],
            })}'
            '${chunk({}, finish: 'tool_calls')}data: [DONE]\n\n',
          ),
        ]),
      );
      expect(events.indexWhere((e) => e is ThinkingComplete), 1);
      expect(events[2], isA<ToolCallDelta>());
    });

    test('Fehler-Chunk mitten im Tool-Call → ServerException', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(fixture('openai/error_during_tool_call.sse')),
        ]),
      );
      final error = (events.last as ErrorEvent).error;
      expect(error, isA<ServerException>());
      expect(error.message, contains('server had an error'));
      expect(events.whereType<ToolCallComplete>(), isEmpty);
    });

    for (final (name, error, type) in [
      (
        'rate_limit',
        '{"message":"slow","type":"rate_limit_error"}',
        RateLimitException,
      ),
      ('auth', '{"message":"no","type":"authentication_error"}', AuthException),
      (
        'invalid',
        '{"message":"bad","type":"invalid_request_error"}',
        InvalidRequestException,
      ),
      ('timeout', '{"message":"t","type":"timeout"}', ProviderTimeoutException),
      ('Zahlencode 503', '{"message":"busy","code":503}', ServerException),
      ('Text statt Objekt', '"kaputt"', ServerException),
    ]) {
      test('Fehler-Chunk $name → $type', () async {
        final events = await run(
          FakeServer([FakeResponse.sse('data: {"error":$error}\n\n')]),
        );
        expect((events.single as ErrorEvent).error.runtimeType, type);
      });
    }

    test('kaputte Zeile → Malformed', () async {
      final events = await run(
        FakeServer([FakeResponse.sse(fixture('openai/broken_line.sse'))]),
      );
      expect(events.first, const TextDelta('Hal'));
      expect(
        (events.last as ErrorEvent).error,
        isA<MalformedResponseException>(),
      );
    });

    test('Stream ohne finish_reason und [DONE] → NetworkException', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(chunk({'content': 'Hal'})),
        ]),
      );
      expect((events.last as ErrorEvent).error, isA<NetworkException>());
    });

    test(
      'finish_reason ohne [DONE] (z. B. Ollama) endet trotzdem mit Done',
      () async {
        final events = await run(
          FakeServer([
            FakeResponse.sse(
              '${chunk({'content': 'ok'})}${chunk({}, finish: 'stop')}',
            ),
          ]),
        );
        expect(events.last, const Done(StopReason.endTurn));
      },
    );

    test('[DONE] ohne finish_reason, Tool-Calls ohne index/id, '
        '"stop" mit Tool-Call → toolUse', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({
              'tool_calls': [
                {
                  'function': {'name': 'a', 'arguments': '{"x":1}'},
                },
                {
                  'function': {
                    'name': 'b',
                    'arguments': {'y': 2},
                  },
                },
              ],
            })}'
            'data: [DONE]\n\n',
          ),
        ]),
      );
      final calls = [
        for (final e in events.whereType<ToolCallComplete>()) e.call,
      ];
      expect(calls, [
        const ToolCallBlock(id: 'call_0', name: 'a', argumentsJson: '{"x":1}'),
        const ToolCallBlock(id: 'call_1', name: 'b', argumentsJson: '{"y":2}'),
      ]);
      expect(events.last, const Done(StopReason.toolUse));
    });

    test('Name im späteren Fragment, leere Argumente → "{}"', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({
              'tool_calls': [
                {'index': 0, 'id': 'c'},
              ],
            })}'
            '${chunk({
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'name': 'spaet'},
                },
              ],
            })}'
            '${chunk({}, finish: 'tool_calls')}',
          ),
        ]),
      );
      expect(
        events.whereType<ToolCallComplete>().single.call,
        const ToolCallBlock(id: 'c', name: 'spaet', argumentsJson: '{}'),
      );
    });

    test('Tool-Call ohne Namen → Malformed', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'c',
                  'function': {'arguments': '{}'},
                },
              ],
            })}'
            '${chunk({}, finish: 'tool_calls')}',
          ),
        ]),
      );
      expect(
        (events.last as ErrorEvent).error,
        isA<MalformedResponseException>(),
      );
    });

    test('Tool-Fragment nach finish_reason → Malformed', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({}, finish: 'stop')}'
            '${chunk({
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'name': 'n'},
                },
              ],
            })}',
          ),
        ]),
      );
      expect(
        (events.last as ErrorEvent).error,
        isA<MalformedResponseException>(),
      );
    });

    test('finish_reason-Mapping', () async {
      for (final (wire, expected) in [
        ('stop', StopReason.endTurn),
        ('tool_calls', StopReason.toolUse),
        ('function_call', StopReason.toolUse),
        ('length', StopReason.maxTokens),
        ('content_filter', StopReason.refusal),
        ('neu', StopReason.other),
      ]) {
        final events = await run(
          FakeServer([
            FakeResponse.sse('${chunk({}, finish: wire)}data: [DONE]\n\n'),
          ]),
        );
        expect(events.last, Done(expected), reason: wire);
      }
    });

    test('kumulative Usage in jedem Chunk (vLLM) → nur Zuwachs', () async {
      String usageChunk(String content, int prompt, int completion) =>
          'data: {"choices":[{"index":0,"delta":{"content":"$content"}}],'
          '"usage":{"prompt_tokens":$prompt,"completion_tokens":$completion,'
          '"prompt_tokens_details":{"cached_tokens":4}}}\n\n';
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${usageChunk('a', 10, 1)}${usageChunk('b', 10, 2)}'
            '${usageChunk('c', 10, 3)}${chunk({}, finish: 'stop')}'
            'data: {"choices":[],"usage":{"prompt_tokens":10,'
            '"completion_tokens":3,"prompt_tokens_details":{"cached_tokens":4}}}\n\n'
            'data: [DONE]\n\n',
          ),
        ]),
      );
      expect(events.whereType<UsageEvent>().map((e) => e.usage), [
        const Usage(inputTokens: 6, outputTokens: 1, cachedInputTokens: 4),
        const Usage(outputTokens: 1),
        const Usage(outputTokens: 1),
      ]);
    });

    test('Usage ohne Cache-Details und Null-Usage', () async {
      final events = await run(
        FakeServer([
          FakeResponse.sse(
            '${chunk({}, finish: 'stop')}'
            'data: {"choices":[],"usage":{"prompt_tokens":0,"completion_tokens":0}}\n\n'
            'data: [DONE]\n\n',
          ),
        ]),
      );
      expect(events.whereType<UsageEvent>(), isEmpty);
    });
  });

  group('OpenAiChatAdapter – HTTP', () {
    test(
      'Request: URL, Bearer, max_completion_tokens bei api.openai.com',
      () async {
        final server = FakeServer([
          FakeResponse.sse(fixture('openai/text.sse')),
        ]);
        await adapter(server).chat(sampleRequest()).toList();
        final r = server.requests.single;
        expect(r.url.toString(), 'https://api.openai.com/v1/chat/completions');
        expect(r.headers['Authorization'], 'Bearer $_key');
        expect(r.json['max_completion_tokens'], 1024);
        expect(r.json.containsKey('max_tokens'), isFalse);
      },
    );

    test(
      'andere Server: max_tokens, Base-URL mit Schrägstrich, keine Auth',
      () async {
        final server = FakeServer([
          FakeResponse.sse(fixture('openai/text.sse')),
        ]);
        await adapter(
          server,
          baseUrl: 'http://localhost:11434/v1/',
          credentials: Credentials.none(),
        ).chat(sampleRequest()).toList();
        final r = server.requests.single;
        expect(r.url.toString(), 'http://localhost:11434/v1/chat/completions');
        expect(
          r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(r.json['max_tokens'], 1024);
      },
    );

    test('maxTokensField-Option überschreibt die Voreinstellung', () async {
      final server = FakeServer([FakeResponse.sse(fixture('openai/text.sse'))]);
      await adapter(
        server,
        options: const OpenAiOptions(maxTokensField: 'max_tokens'),
      ).chat(sampleRequest()).toList();
      expect(server.requests.single.json['max_tokens'], 1024);
    });

    test(
      'stream_options abgelehnt → einmal ohne wiederholen und merken',
      () async {
        final server = FakeServer([
          FakeResponse.json(400, fixture('openai/400_stream_options.json')),
          FakeResponse.sse(fixture('openai/text.sse')),
          FakeResponse.sse(fixture('openai/text.sse')),
        ]);
        final a = adapter(server, baseUrl: 'http://vllm.local/v1');
        final events = await a.chat(sampleRequest()).toList();
        expect(events.last, const Done(StopReason.endTurn));
        expect(server.requests, hasLength(2));
        expect(server.requests[0].json.containsKey('stream_options'), isTrue);
        expect(server.requests[1].json.containsKey('stream_options'), isFalse);
        await a.chat(sampleRequest()).toList();
        expect(server.requests, hasLength(3));
        expect(server.requests[2].json.containsKey('stream_options'), isFalse);
      },
    );

    test('andere 400-Fehler werden nicht wiederholt', () async {
      final server = FakeServer([
        const FakeResponse.json(400, '{"error":{"message":"model not found"}}'),
      ]);
      final events = await adapter(server).chat(sampleRequest()).toList();
      expect(
        (events.single as ErrorEvent).error,
        isA<InvalidRequestException>(),
      );
      expect(server.requests, hasLength(1));
    });

    test('includeUsage: false sendet nie stream_options', () async {
      final server = FakeServer([
        FakeResponse.json(400, fixture('openai/400_stream_options.json')),
      ]);
      final events = await adapter(
        server,
        options: const OpenAiOptions(includeUsage: false),
      ).chat(sampleRequest()).toList();
      expect(
        (events.single as ErrorEvent).error,
        isA<InvalidRequestException>(),
      );
      expect(
        server.requests.single.json.containsKey('stream_options'),
        isFalse,
      );
    });

    for (final (status, body, type) in [
      (401, fixture('openai/401.json'), AuthException),
      (429, fixture('openai/429.json'), RateLimitException),
      (500, fixture('openai/500.json'), ServerException),
      (503, 'Service Unavailable', ServerException),
      (504, '<html>Gateway Timeout</html>', ProviderTimeoutException),
      (422, '{"detail":"bad"}', InvalidRequestException),
    ]) {
      test('HTTP $status → $type', () async {
        final events = await run(FakeServer([FakeResponse.json(status, body)]));
        final error = (events.single as ErrorEvent).error;
        expect(error.runtimeType, type);
        expect(error.message, contains('OpenAI: HTTP $status'));
      });
    }

    test('429 insufficient_quota → AuthException', () async {
      final events = await run(
        FakeServer([
          const FakeResponse.json(
            429,
            '{"error":{"message":"You exceeded your current quota","type":"insufficient_quota","code":"insufficient_quota"}}',
          ),
        ]),
      );
      final error = (events.single as ErrorEvent).error;
      expect(error, isA<AuthException>());
      expect(error.message, contains('Guthaben'));
    });

    test('retry-after-ms wird gelesen', () async {
      final events = await run(
        FakeServer([
          FakeResponse.json(
            429,
            fixture('openai/429.json'),
            headers: {'retry-after-ms': '1500'},
          ),
        ]),
      );
      expect(
        ((events.single as ErrorEvent).error as RateLimitException).retryAfter,
        const Duration(milliseconds: 1500),
      );
    });

    test('Abbruch schließt die Verbindung', () async {
      final server = FakeServer([
        const FakeResponse.hang(
          'data: {"choices":[{"delta":{"content":"x"}}]}\n\n',
        ),
      ]);
      final cancel = CancelToken();
      final events = <ChatEvent>[];
      await for (final e in adapter(
        server,
      ).chat(sampleRequest(), cancel: cancel)) {
        events.add(e);
        cancel.cancel();
      }
      expect(events.last, const ErrorEvent(CancelledException()));
      await pumpEventQueue();
      expect(server.bodyCancelled, isTrue);
      expect(server.aborted, isTrue);
    });

    test('caps, type, toString ohne Key', () {
      final a = adapter(FakeServer([]));
      expect(a.type, ProviderType.openaiCompatible);
      expect(a.caps.tools, isTrue);
      expect(a.toString(), contains('OpenAI'));
      expect(a.toString(), isNot(contains(_key)));
    });
  });

  group('OpenAiChatAdapter – listModels und test()', () {
    test('listModels mit Kontext und Tool-Fähigkeit', () async {
      final models = await adapter(
        FakeServer([FakeResponse.json(200, fixture('openai/models.json'))]),
      ).listModels();
      expect(models, [
        const ModelInfo(
          id: 'z-ai/glm-5.3-flash',
          displayName: 'GLM 5.3 Flash',
          contextWindow: 1048576,
          supportsTools: true,
        ),
        const ModelInfo(
          id: 'some/other-model',
          contextWindow: 32768,
          supportsTools: false,
        ),
        const ModelInfo(id: 'gpt-4.1-nano'),
      ]);
    });

    test('teeModelsOnly filtert auf is_tee', () async {
      final models = await adapter(
        FakeServer([FakeResponse.json(200, fixture('openai/models.json'))]),
        options: const OpenAiOptions(teeModelsOnly: true),
      ).listModels();
      expect(models.map((m) => m.id), ['z-ai/glm-5.3-flash']);
    });

    test('test(): Tool-Aufruf erkannt', () async {
      final server = FakeServer([
        FakeResponse.json(200, fixture('openai/models.json')),
        FakeResponse.sse(
          fixture('openai/tool_call.sse')
              .replaceAll('contract__echo', 'wendelin__ping'),
        ),
      ]);
      final health = await adapter(server).test();
      expect(health.ok, isTrue);
      expect(health.detected?.tools, isTrue);
      expect(health.models, hasLength(3));
    });

    test('test(): Server ohne Modellliste, Tool-Aufruf klappt', () async {
      final health = await adapter(
        FakeServer([
          const FakeResponse.json(404, 'not found'),
          FakeResponse.sse(
            fixture('openai/tool_call.sse')
                .replaceAll('contract__echo', 'wendelin__ping'),
          ),
        ]),
      ).test();
      expect(health.ok, isTrue);
      expect(health.models, isNull);
      expect(health.detected?.tools, isTrue);
    });
  });
}
