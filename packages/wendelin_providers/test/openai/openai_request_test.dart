import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/src/openai/openai_options.dart';
import 'package:wendelin_providers/src/openai/openai_request.dart';

import '../support/sample_conversation.dart';

Map<String, Object?> build(
  ChatRequest req, {
  OpenAiOptions options = const OpenAiOptions(),
  String maxTokensField = 'max_tokens',
  bool includeUsage = true,
}) => buildOpenAiBody(
  req,
  options,
  maxTokensField: maxTokensField,
  includeUsage: includeUsage,
);

void main() {
  group('buildOpenAiBody', () {
    test('Snapshot der Beispielkonversation', () {
      expect(build(sampleRequest()), {
        'model': 'test-model',
        'messages': [
          {
            'role': 'system',
            'content': 'Du bist Wendelin. Heute ist Dienstag.',
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$pngBase64'},
              },
              {
                'type': 'text',
                'text': 'Trag das Tauchen von diesem Flyer ein.',
              },
            ],
          },
          {
            'role': 'assistant',
            'content': 'Ich trage es ein.',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'calendar__create',
                  'arguments': '{"title":"Tauchen","start":"2026-10-14T10:00"}',
                },
              },
            ],
          },
          {
            'role': 'tool',
            'tool_call_id': 'call_1',
            'content': 'Termin angelegt',
          },
          {'role': 'user', 'content': 'Danke!'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'calendar__create',
              'description': 'Legt einen Termin an.',
              'parameters': calendarTool.inputSchema,
            },
          },
        ],
        'max_tokens': 1024,
        'temperature': 0.2,
        'stream': true,
        'stream_options': {'include_usage': true},
      });
    });

    test('Tool-Choice-Mapping', () {
      Object? choice(ToolChoice c) =>
          build(sampleRequest(toolChoice: c))['tool_choice'];
      expect(choice(ToolChoice.auto), isNull);
      expect(choice(ToolChoice.none), 'none');
      expect(choice(ToolChoice.required), 'required');
      expect(choice(const ToolChoice.tool('calendar__create')), {
        'type': 'function',
        'function': {'name': 'calendar__create'},
      });
    });

    test('ohne Tools, ohne System, ohne Usage-Option', () {
      final body = build(
        ChatRequest(
          messages: [Message.user('Hi')],
          model: 'm',
          maxTokens: 10,
          toolChoice: ToolChoice.required,
        ),
        maxTokensField: 'max_completion_tokens',
        includeUsage: false,
      );
      expect(body, {
        'model': 'm',
        'messages': [
          {'role': 'user', 'content': 'Hi'},
        ],
        'max_completion_tokens': 10,
        'stream': true,
      });
    });

    test('Optionen: reasoning_effort, disableReasoning, extraBody', () {
      final body = build(
        ChatRequest(messages: [Message.user('x')], model: 'm', maxTokens: 5),
        options: const OpenAiOptions(
          reasoningEffort: 'low',
          disableReasoning: true,
          extraBody: {'top_k': 5},
        ),
      );
      expect(body['reasoning_effort'], 'low');
      expect(body['reasoning'], {'enabled': false});
      expect(body['top_k'], 5);
    });

    test('Rollen und Sonderfälle', () {
      final body = build(
        ChatRequest(
          messages: [
            Message.system('Regel'),
            Message.system(''),
            Message(Role.user, const [TextBlock('a'), TextBlock('b')]),
            Message(Role.user, const [TextBlock('')]),
            Message.assistant(const [ThinkingBlock('nur gedacht')]),
            Message.assistant(const [
              ToolCallBlock(id: 'c', name: 'n', argumentsJson: '{}'),
            ]),
            Message.toolResults([
              ToolResultBlock(
                callId: 'c',
                isError: true,
                content: [
                  const TextBlock('kaputt'),
                  ImageBlock.base64(mediaType: 'image/png', data: pngBase64),
                ],
              ),
            ]),
          ],
          model: 'm',
          maxTokens: 5,
        ),
      );
      expect(body['messages'], [
        {'role': 'system', 'content': 'Regel'},
        {'role': 'user', 'content': 'a\nb'},
        {
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'id': 'c',
              'type': 'function',
              'function': {'name': 'n', 'arguments': '{}'},
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'c',
          'content': 'Fehler: kaputt\n[Bild: image/png]',
        },
      ]);
    });
  });

  test('Tools nach Name sortiert', () {
    ToolSpec tool(String name) => ToolSpec(
      name: name,
      description: name,
      inputSchema: const {'type': 'object'},
    );
    final body = build(
      ChatRequest(
        messages: [Message.user('x')],
        tools: [tool('zeta__a'), tool('alpha__b')],
        model: 'm',
        maxTokens: 10,
      ),
    );
    expect(
      [
        for (final t in body['tools']! as List<Object?>)
          ((t! as Map)['function'] as Map)['name'],
      ],
      ['alpha__b', 'zeta__a'],
    );
  });

  group('OpenAiOptions.fromMap', () {
    test('liest bekannte Schlüssel, ignoriert falsche Typen', () {
      final o = OpenAiOptions.fromMap({
        'reasoningEffort': 'minimal',
        'disableReasoning': true,
        'emitReasoning': false,
        'maxTokensField': 'max_completion_tokens',
        'includeUsage': false,
        'teeModelsOnly': true,
        'extraBody': {'seed': 1},
      });
      expect(o.reasoningEffort, 'minimal');
      expect(o.disableReasoning, isTrue);
      expect(o.emitReasoning, isFalse);
      expect(o.maxTokensField, 'max_completion_tokens');
      expect(o.includeUsage, isFalse);
      expect(o.teeModelsOnly, isTrue);
      expect(o.extraBody, {'seed': 1});
      final d = OpenAiOptions.fromMap({
        'emitReasoning': 'nein',
        'extraBody': 3,
      });
      expect(d.emitReasoning, isTrue);
      expect(d.includeUsage, isTrue);
      expect(d.extraBody, isEmpty);
      expect(d.disableReasoning, isFalse);
      expect(d.teeModelsOnly, isFalse);
    });
  });
}
