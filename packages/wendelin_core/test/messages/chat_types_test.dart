import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('Usage', () {
    test('+ adds every field separately', () {
      const a = Usage(
        inputTokens: 1,
        outputTokens: 20,
        cachedInputTokens: 300,
        cacheWriteTokens: 4000,
      );
      const b = Usage(
        inputTokens: 5,
        outputTokens: 60,
        cachedInputTokens: 700,
        cacheWriteTokens: 8000,
      );
      expect(
        a + b,
        const Usage(
          inputTokens: 6,
          outputTokens: 80,
          cachedInputTokens: 1000,
          cacheWriteTokens: 12000,
        ),
      );
      expect(a + Usage.zero, a);
      expect(Usage.zero + Usage.zero, Usage.zero);
    });

    test('totalTokens sums all four counts', () {
      expect(
        const Usage(
          inputTokens: 1,
          outputTokens: 2,
          cachedInputTokens: 4,
          cacheWriteTokens: 8,
        ).totalTokens,
        15,
      );
    });

    test('equality per field', () {
      const base = Usage(
        inputTokens: 1,
        outputTokens: 1,
        cachedInputTokens: 1,
        cacheWriteTokens: 1,
      );
      expect(
        base,
        isNot(
          const Usage(
            outputTokens: 1,
            cachedInputTokens: 1,
            cacheWriteTokens: 1,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const Usage(
            inputTokens: 1,
            cachedInputTokens: 1,
            cacheWriteTokens: 1,
          ),
        ),
      );
      expect(
        base,
        isNot(
          const Usage(inputTokens: 1, outputTokens: 1, cacheWriteTokens: 1),
        ),
      );
      expect(
        base,
        isNot(
          const Usage(inputTokens: 1, outputTokens: 1, cachedInputTokens: 1),
        ),
      );
      expect(
        base.hashCode,
        const Usage(
          inputTokens: 1,
          outputTokens: 1,
          cachedInputTokens: 1,
          cacheWriteTokens: 1,
        ).hashCode,
      );
      expect(base.toString(), contains('cacheWrite: 1'));
    });
  });

  group('ToolChoice', () {
    test('constants and tool()', () {
      expect(ToolChoice.auto, isA<ToolChoiceAuto>());
      expect(ToolChoice.none, isA<ToolChoiceNone>());
      expect(ToolChoice.required, isA<ToolChoiceRequired>());
      expect(const ToolChoice.tool('a'), const ToolChoiceTool('a'));
      expect(const ToolChoice.tool('a'), isNot(const ToolChoice.tool('b')));
      expect(ToolChoice.auto, isNot(ToolChoice.none));
      expect(ToolChoice.none, isNot(ToolChoice.required));
      expect(ToolChoice.required, isNot(ToolChoice.auto));
    });

    test('hashCode and toString', () {
      expect(const ToolChoiceAuto().hashCode, ToolChoice.auto.hashCode);
      expect(const ToolChoiceNone().hashCode, ToolChoice.none.hashCode);
      expect(const ToolChoiceRequired().hashCode, ToolChoice.required.hashCode);
      expect(
        const ToolChoice.tool('x').hashCode,
        const ToolChoiceTool('x').hashCode,
      );
      expect(
        [
          ToolChoice.auto,
          ToolChoice.none,
          ToolChoice.required,
          const ToolChoice.tool('x'),
        ].map((c) => c.toString()),
        [
          'ToolChoice.auto',
          'ToolChoice.none',
          'ToolChoice.required',
          'ToolChoice.tool(x)',
        ],
      );
    });
  });

  group('ToolSpec', () {
    test('deep equality on schema', () {
      ToolSpec spec(Object? type) => ToolSpec(
        name: 'a__b',
        description: 'd',
        inputSchema: {
          'type': 'object',
          'properties': {
            'x': {'type': type},
          },
        },
      );
      expect(spec('string'), spec('string'));
      expect(spec('string').hashCode, spec('string').hashCode);
      expect(spec('string'), isNot(spec('number')));
      expect(
        spec('string'),
        isNot(
          ToolSpec(
            name: 'a__c',
            description: 'd',
            inputSchema: spec('string').inputSchema,
          ),
        ),
      );
      expect(
        spec('string'),
        isNot(
          ToolSpec(
            name: 'a__b',
            description: 'e',
            inputSchema: spec('string').inputSchema,
          ),
        ),
      );
      expect(spec('string').toString(), contains('a__b'));
    });
  });

  group('ChatRequest', () {
    final req = ChatRequest(
      messages: [Message.user('hi')],
      model: 'm',
      maxTokens: 100,
    );

    test('defaults', () {
      expect(req.tools, isEmpty);
      expect(req.temperature, isNull);
      expect(req.toolChoice, ToolChoice.auto);
      expect(req.metadata, isEmpty);
      expect(req.systemPrompt, isNull);
      expect(req.toString(), contains('m'));
    });

    test('collections are copied and unmodifiable', () {
      final messages = [Message.user('a')];
      final r = ChatRequest(messages: messages, model: 'm', maxTokens: 1);
      messages.add(Message.user('b'));
      expect(r.messages, hasLength(1));
      expect(() => r.messages.add(Message.user('c')), throwsUnsupportedError);
      expect(
        () => r.tools.add(
          const ToolSpec(name: 'n', description: '', inputSchema: {}),
        ),
        throwsUnsupportedError,
      );
      expect(() => r.metadata['k'] = 'v', throwsUnsupportedError);
    });

    test('copyWith replaces only given fields', () {
      const spec = ToolSpec(name: 't', description: 'd', inputSchema: {});
      final c = req.copyWith(
        messages: [Message.user('neu')],
        tools: [spec],
        model: 'm2',
        maxTokens: 5,
        temperature: 0.5,
        toolChoice: ToolChoice.none,
        metadata: {'session': 's1'},
        systemPrompt: 'sys',
      );
      expect(c.messages, [Message.user('neu')]);
      expect(c.tools, [spec]);
      expect(c.model, 'm2');
      expect(c.maxTokens, 5);
      expect(c.temperature, 0.5);
      expect(c.toolChoice, ToolChoice.none);
      expect(c.metadata, {'session': 's1'});
      expect(c.systemPrompt, 'sys');

      final same = c.copyWith();
      expect(same.messages, c.messages);
      expect(same.tools, c.tools);
      expect(same.model, c.model);
      expect(same.maxTokens, c.maxTokens);
      expect(same.temperature, c.temperature);
      expect(same.toolChoice, c.toolChoice);
      expect(same.metadata, c.metadata);
      expect(same.systemPrompt, c.systemPrompt);
    });
  });

  group('ChatEvent', () {
    const call = ToolCallBlock(id: 'i', name: 'n', argumentsJson: '{}');
    final events = <ChatEvent, bool>{
      const TextDelta('a'): false,
      const ThinkingDelta('a'): false,
      const ToolCallDelta(index: 0, id: 'i', name: 'n', argumentsFragment: '{'):
          false,
      const ToolCallComplete(call): false,
      const UsageEvent(Usage.zero): false,
      const Done(StopReason.endTurn): true,
      const ErrorEvent(NetworkException('weg')): true,
    };

    test('only Done and ErrorEvent are terminal', () {
      events.forEach((event, terminal) {
        expect(event.isTerminal, terminal, reason: '$event');
      });
    });

    test('value equality, hashCode and toString', () {
      final copies = <ChatEvent>[
        const TextDelta('a'),
        const ThinkingDelta('a'),
        const ToolCallDelta(
          index: 0,
          id: 'i',
          name: 'n',
          argumentsFragment: '{',
        ),
        const ToolCallComplete(call),
        const UsageEvent(Usage.zero),
        const Done(StopReason.endTurn),
        const ErrorEvent(NetworkException('weg')),
      ];
      for (final (i, e) in events.keys.indexed) {
        expect(copies[i], e);
        expect(copies[i].hashCode, e.hashCode);
        expect(e.toString(), isNotEmpty);
      }
    });

    test('inequality', () {
      expect(const TextDelta('a'), isNot(const TextDelta('b')));
      expect(const TextDelta('a'), isNot(const ThinkingDelta('a')));
      expect(const ThinkingDelta('a'), isNot(const ThinkingDelta('b')));
      const d = ToolCallDelta(
        index: 0,
        id: 'i',
        name: 'n',
        argumentsFragment: 'x',
      );
      expect(
        d,
        isNot(
          const ToolCallDelta(
            index: 1,
            id: 'i',
            name: 'n',
            argumentsFragment: 'x',
          ),
        ),
      );
      expect(
        d,
        isNot(
          const ToolCallDelta(
            index: 0,
            id: 'j',
            name: 'n',
            argumentsFragment: 'x',
          ),
        ),
      );
      expect(
        d,
        isNot(
          const ToolCallDelta(
            index: 0,
            id: 'i',
            name: 'm',
            argumentsFragment: 'x',
          ),
        ),
      );
      expect(
        d,
        isNot(
          const ToolCallDelta(
            index: 0,
            id: 'i',
            name: 'n',
            argumentsFragment: 'y',
          ),
        ),
      );
      expect(
        const ToolCallComplete(call),
        isNot(
          const ToolCallComplete(
            ToolCallBlock(id: 'k', name: 'n', argumentsJson: '{}'),
          ),
        ),
      );
      expect(
        const UsageEvent(Usage.zero),
        isNot(const UsageEvent(Usage(inputTokens: 1))),
      );
      expect(
        const Done(StopReason.endTurn),
        isNot(const Done(StopReason.toolUse)),
      );
      expect(
        const ErrorEvent(NetworkException('a')),
        isNot(const ErrorEvent(NetworkException('b'))),
      );
    });

    test('ToolCallDelta defaults', () {
      const d = ToolCallDelta(index: 2);
      expect(d.id, isNull);
      expect(d.name, isNull);
      expect(d.argumentsFragment, '');
    });
  });
}
