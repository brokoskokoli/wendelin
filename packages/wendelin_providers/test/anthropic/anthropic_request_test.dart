import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/src/anthropic/anthropic_options.dart';
import 'package:wendelin_providers/src/anthropic/anthropic_request.dart';

import '../support/sample_conversation.dart';

void main() {
  group('buildAnthropicBody', () {
    test('Snapshot der Beispielkonversation', () {
      final body = buildAnthropicBody(
        sampleRequest(),
        const AnthropicOptions(),
      );
      expect(body, {
        'model': 'test-model',
        'max_tokens': 1024,
        'system': [
          {
            'type': 'text',
            'text': 'Du bist Wendelin. Heute ist Dienstag.',
            'cache_control': {'type': 'ephemeral'},
          },
        ],
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/png',
                  'data': pngBase64,
                },
              },
              {
                'type': 'text',
                'text': 'Trag das Tauchen von diesem Flyer ein.',
              },
            ],
          },
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'thinking',
                'thinking': 'Flyer lesen.',
                'signature': 'sig-abc',
              },
              {'type': 'redacted_thinking', 'data': 'opaque-data'},
              {'type': 'text', 'text': 'Ich trage es ein.'},
              {
                'type': 'tool_use',
                'id': 'call_1',
                'name': 'calendar__create',
                'input': {'title': 'Tauchen', 'start': '2026-10-14T10:00'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'call_1',
                'content': [
                  {'type': 'text', 'text': 'Termin angelegt'},
                ],
              },
              {'type': 'text', 'text': 'Danke!'},
            ],
          },
        ],
        'tools': [
          {
            'name': 'calendar__create',
            'description': 'Legt einen Termin an.',
            'input_schema': calendarTool.inputSchema,
            'cache_control': {'type': 'ephemeral'},
          },
        ],
        'temperature': 0.2,
        'cache_control': {'type': 'ephemeral'},
        'stream': true,
      });
    });

    test('Tool-Choice-Mapping', () {
      Object? choice(ToolChoice c) => buildAnthropicBody(
        sampleRequest(toolChoice: c),
        const AnthropicOptions(),
      )['tool_choice'];
      expect(choice(ToolChoice.auto), isNull);
      expect(choice(ToolChoice.none), {'type': 'none'});
      expect(choice(ToolChoice.required), {'type': 'any'});
      expect(choice(const ToolChoice.tool('calendar__create')), {
        'type': 'tool',
        'name': 'calendar__create',
      });
    });

    test('ohne Tools kein tools/tool_choice, ohne System kein system', () {
      final body = buildAnthropicBody(
        ChatRequest(
          messages: [Message.user('Hi')],
          model: 'm',
          maxTokens: 10,
          toolChoice: ToolChoice.required,
        ),
        const AnthropicOptions(cacheConversation: false),
      );
      expect(body.keys, ['model', 'max_tokens', 'messages', 'stream']);
    });

    test('Web-Suche als erstes Tool, cache_control auf dem letzten', () {
      final body = buildAnthropicBody(
        sampleRequest().copyWith(model: 'claude-sonnet-5-5'),
        const AnthropicOptions(
          enableServerWebSearch: true,
          webSearchMaxUses: 2,
        ),
      );
      final tools = body['tools']! as List<Object?>;
      expect(tools.first, {
        'type': 'web_search_20260209',
        'name': 'web_search',
        'max_uses': 2,
      });
      expect((tools.last! as Map)['name'], 'calendar__create');
      expect((tools.last! as Map)['cache_control'], {'type': 'ephemeral'});
    });

    test('Web-Suche: Basisversion für ältere Modelle, Override', () {
      Object? type(String model, {String? override}) =>
          ((buildAnthropicBody(
                        ChatRequest(
                          messages: [Message.user('x')],
                          model: model,
                          maxTokens: 10,
                        ),
                        AnthropicOptions(
                          enableServerWebSearch: true,
                          webSearchToolType: override,
                        ),
                      )['tools']!
                      as List<Object?>)
                  .single!
              as Map)['type'];
      expect(type('claude-haiku-5-5'), 'web_search_20250305');
      expect(type('claude-opus-4-6-20260101'), 'web_search_20260209');
      expect(type('claude-opus-4-60'), 'web_search_20250305');
      expect(type('claude-haiku-5-5', override: 'x_1'), 'x_1');
    });

    test('Thinking- und Effort-Optionen', () {
      Map<String, Object?> body(AnthropicOptions o) =>
          buildAnthropicBody(sampleRequest(), o);
      expect(body(const AnthropicOptions(thinking: 'adaptive'))['thinking'], {
        'type': 'adaptive',
      });
      expect(
        body(
          const AnthropicOptions(
            thinking: 'adaptive',
            thinkingDisplay: 'summarized',
          ),
        )['thinking'],
        {'type': 'adaptive', 'display': 'summarized'},
      );
      expect(body(const AnthropicOptions(thinking: 'disabled'))['thinking'], {
        'type': 'disabled',
      });
      expect(
        body(const AnthropicOptions(thinking: 'between_tools'))['thinking'],
        {'type': 'between_tools'},
      );
      expect(body(const AnthropicOptions(thinkingBudget: 2000))['thinking'], {
        'type': 'enabled',
        'budget_tokens': 2000,
      });
      expect(
        body(const AnthropicOptions(thinkingBudget: 0)).containsKey('thinking'),
        isFalse,
      );
      expect(
        body(const AnthropicOptions(reasoningEffort: 'low'))['output_config'],
        {'effort': 'low'},
      );
    });

    test('Role.system wird an den System-Prompt angehängt', () {
      final body = buildAnthropicBody(
        ChatRequest(
          systemPrompt: 'A',
          messages: [Message.system('B'), Message.user('x')],
          model: 'm',
          maxTokens: 10,
        ),
        const AnthropicOptions(),
      );
      expect(body['system'], [
        {
          'type': 'text',
          'text': 'A',
          'cache_control': {'type': 'ephemeral'},
        },
        {'type': 'text', 'text': 'B'},
      ]);
      expect((body['messages']! as List).length, 1);
    });

    test('leere Texte entfallen, Fehler-Ergebnis mit is_error, Bild im '
        'Ergebnis, kaputte Argumente als _raw', () {
      final body = buildAnthropicBody(
        ChatRequest(
          messages: [
            Message(Role.user, const [TextBlock(''), TextBlock('x')]),
            Message.assistant(const [
              ToolCallBlock(id: 'c', name: 'n', argumentsJson: '{kaputt'),
            ]),
            Message.toolResults([
              ToolResultBlock(
                callId: 'c',
                isError: true,
                content: [
                  const TextBlock('Fehler'),
                  ImageBlock.base64(mediaType: 'image/png', data: pngBase64),
                ],
              ),
              ToolResultBlock(callId: 'd', content: const []),
            ]),
            Message.assistant(const [TextBlock('')]),
          ],
          model: 'm',
          maxTokens: 10,
        ),
        const AnthropicOptions(),
      );
      final messages = body['messages']! as List<Object?>;
      expect(messages, hasLength(3));
      expect((messages[0]! as Map)['content'], [
        {'type': 'text', 'text': 'x'},
      ]);
      expect(((messages[1]! as Map)['content'] as List).single, {
        'type': 'tool_use',
        'id': 'c',
        'name': 'n',
        'input': {'_raw': '{kaputt'},
      });
      final results = (messages[2]! as Map)['content'] as List<Object?>;
      expect(results[0], {
        'type': 'tool_result',
        'tool_use_id': 'c',
        'content': [
          {'type': 'text', 'text': 'Fehler'},
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': 'image/png',
              'data': pngBase64,
            },
          },
        ],
        'is_error': true,
      });
      expect(results[1], {'type': 'tool_result', 'tool_use_id': 'd'});
    });

    test('Eskalation: fremder Verlauf ohne Thinking bei aktivem Thinking '
        'wird unverändert gesendet', () {
      // Nach einer Eskalation enthält der Verlauf Assistant-Turns mit
      // Tool-Calls ohne (Anthropic-)Thinking. Die API verlangt laut Doku
      // (Thinking with tool use) bei adaptive kein führendes Thinking und
      // degradiert bei manuellem Thinking still statt mit Fehler; der
      // Adapter erfindet daher nichts und lässt den Verlauf wie er ist.
      final history = [
        Message.user('Trag Tauchen ein.'),
        Message.assistant(const [
          ThinkingBlock('Reasoning von GLM'), // ohne Signatur: entfällt
          ToolCallBlock(
            id: 'call_glm_1',
            name: 'calendar__create',
            argumentsJson: '{"title":"Tauchen"}',
          ),
        ]),
        Message.toolResults([
          ToolResultBlock(
            callId: 'call_glm_1',
            content: const [TextBlock('ok')],
          ),
        ]),
      ];
      for (final options in const [
        AnthropicOptions(thinking: 'adaptive'),
        AnthropicOptions(thinkingBudget: 2048),
      ]) {
        final body = buildAnthropicBody(
          ChatRequest(
            messages: history,
            tools: const [calendarTool],
            model: 'claude-sonnet-5-5',
            maxTokens: 4096,
          ),
          options,
        );
        expect(body['thinking'], isNotNull);
        expect(body['messages'], [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Trag Tauchen ein.'},
            ],
          },
          {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': 'call_glm_1',
                'name': 'calendar__create',
                'input': {'title': 'Tauchen'},
              },
            ],
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': 'call_glm_1',
                'content': [
                  {'type': 'text', 'text': 'ok'},
                ],
              },
            ],
          },
        ]);
      }
    });

    test('pause_turn-Fortsetzung: Server-Blöcke unverändert an ihrer '
        'Position, server_tool_use als letzter Block', () {
      const serverToolUse =
          '{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search",'
          '"input":{"query":"Wetter Nizza"}}';
      const searchResult =
          '{"type":"web_search_tool_result","tool_use_id":"srvtoolu_0",'
          '"content":[{"type":"web_search_result","title":"T",'
          '"url":"https://x.example","encrypted_content":"Eq1"}]}';
      final body = buildAnthropicBody(
        ChatRequest(
          messages: [
            Message.user('Wie wird das Wetter in Nizza?'),
            Message.assistant(const [
              ProviderBlock(provider: 'anthropic', rawJson: searchResult),
              TextBlock('Ich suche weiter.'),
              ProviderBlock(provider: 'openaiCompatible', rawJson: '{"x":1}'),
              ProviderBlock(provider: 'anthropic', rawJson: 'kein json'),
              ProviderBlock(provider: 'anthropic', rawJson: '[1]'),
              ProviderBlock(
                provider: 'anthropic',
                rawJson: serverToolUse,
                summary: 'Websuche: Wetter Nizza',
              ),
            ]),
          ],
          model: 'claude-sonnet-5-5',
          maxTokens: 100,
        ),
        const AnthropicOptions(
          enableServerWebSearch: true,
          cacheConversation: false,
        ),
      );
      expect(body['messages'], [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'Wie wird das Wetter in Nizza?'},
          ],
        },
        {
          'role': 'assistant',
          'content': [
            jsonDecode(searchResult),
            {'type': 'text', 'text': 'Ich suche weiter.'},
            jsonDecode(serverToolUse),
          ],
        },
      ]);
    });

    test('ProviderBlock in User-Nachricht wird nicht gesendet', () {
      final body = buildAnthropicBody(
        ChatRequest(
          messages: [
            Message(Role.user, const [
              ProviderBlock(provider: 'anthropic', rawJson: '{"type":"x"}'),
              TextBlock('x'),
            ]),
          ],
          model: 'm',
          maxTokens: 10,
        ),
        const AnthropicOptions(),
      );
      expect(((body['messages']! as List).single as Map)['content'], [
        {'type': 'text', 'text': 'x'},
      ]);
    });

    test('Tools nach Name sortiert (Cache-Stabilität)', () {
      ToolSpec tool(String name) => ToolSpec(
        name: name,
        description: name,
        inputSchema: const {'type': 'object'},
      );
      final body = buildAnthropicBody(
        ChatRequest(
          messages: [Message.user('x')],
          tools: [tool('zeta__a'), tool('alpha__b'), tool('mitte__c')],
          model: 'm',
          maxTokens: 10,
        ),
        const AnthropicOptions(),
      );
      final tools = body['tools']! as List<Object?>;
      expect(
        [for (final t in tools) (t! as Map)['name']],
        ['alpha__b', 'mitte__c', 'zeta__a'],
      );
      expect((tools.last! as Map)['cache_control'], {'type': 'ephemeral'});
    });

    test('ohne erzwungene Tool-Wahl: required/tool → auto, none bleibt', () {
      Object? choice(ToolChoice c) => buildAnthropicBody(
        sampleRequest(toolChoice: c),
        const AnthropicOptions(),
        forcedToolChoice: false,
      )['tool_choice'];
      expect(choice(ToolChoice.required), isNull);
      expect(choice(const ToolChoice.tool('calendar__create')), isNull);
      expect(choice(ToolChoice.none), {'type': 'none'});
    });

    test('ohne Sampling-Parameter: keine temperature', () {
      expect(
        buildAnthropicBody(
          sampleRequest(),
          const AnthropicOptions(),
          sampling: false,
        ).containsKey('temperature'),
        isFalse,
      );
    });

    test('ungültige Tool-IDs konsistent in tool_use und tool_result', () {
      List<Object?> idsOf(List<Message> messages) {
        final body = buildAnthropicBody(
          ChatRequest(messages: messages, model: 'm', maxTokens: 10),
          const AnthropicOptions(),
        );
        return [
          for (final m in body['messages']! as List<Object?>)
            for (final b in (m! as Map)['content'] as List<Object?>)
              (b! as Map)['id'] ?? (b as Map)['tool_use_id'],
        ];
      }

      ToolCallBlock call(String id) =>
          ToolCallBlock(id: id, name: 'n', argumentsJson: '{}');
      ToolResultBlock result(String id) =>
          ToolResultBlock(callId: id, content: const [TextBlock('ok')]);
      final messages = [
        Message.user('x'),
        Message.assistant([
          call('call:1'),
          call('a_b'),
          call('a.b'),
          call(''),
          call('gültig-ID_9'),
          call('ok_1'),
        ]),
        Message.toolResults([
          result('call:1'),
          result('a_b'),
          result('a.b'),
          result(''),
          result('gültig-ID_9'),
          result('ok_1'),
        ]),
      ];
      final ids = idsOf(messages);
      expect(ids.sublist(1, 7), [
        'call_1',
        'a_b',
        'a_b_2',
        'call_0',
        'g_ltig-ID_9',
        'ok_1',
      ]);
      // tool_result verweist auf dieselben IDs.
      expect(ids.sublist(7), ids.sublist(1, 7));
      // Alle gültig und eindeutig.
      expect(
        ids.whereType<String>().every(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch),
        isTrue,
      );
      expect(ids.sublist(1, 7).toSet(), hasLength(6));
      // Deterministisch.
      expect(idsOf(messages), ids);
      // Kollision mit gültiger ID, die später kommt: gültige bleibt.
      expect(
        idsOf([
          Message.assistant([call('x.y'), call('x_y')]),
        ]),
        ['x_y_2', 'x_y'],
      );
    });

    test('Thinking in User-Nachrichten wird nicht gesendet', () {
      final body = buildAnthropicBody(
        ChatRequest(
          messages: [
            Message(Role.user, const [
              ThinkingBlock('t', signature: 's'),
              ThinkingBlock.redacted('r'),
              TextBlock('x'),
            ]),
          ],
          model: 'm',
          maxTokens: 10,
        ),
        const AnthropicOptions(),
      );
      expect(((body['messages']! as List).single as Map)['content'], [
        {'type': 'text', 'text': 'x'},
      ]);
    });
  });

  group('AnthropicOptions.fromMap', () {
    test('liest bekannte Schlüssel, ignoriert falsche Typen', () {
      final o = AnthropicOptions.fromMap({
        'enableServerWebSearch': true,
        'webSearchMaxUses': 5,
        'webSearchToolType': 'web_search_x',
        'thinking': 'adaptive',
        'thinkingDisplay': 'summarized',
        'thinkingBudget': 1024,
        'reasoningEffort': 'high',
        'cacheConversation': false,
      });
      expect(o.enableServerWebSearch, isTrue);
      expect(o.webSearchMaxUses, 5);
      expect(o.webSearchToolType, 'web_search_x');
      expect(o.thinking, 'adaptive');
      expect(o.thinkingDisplay, 'summarized');
      expect(o.thinkingBudget, 1024);
      expect(o.reasoningEffort, 'high');
      expect(o.cacheConversation, isFalse);

      final d = AnthropicOptions.fromMap({
        'enableServerWebSearch': 'ja',
        'thinkingBudget': '1000',
      });
      expect(d.enableServerWebSearch, isFalse);
      expect(d.thinkingBudget, isNull);
      expect(d.webSearchMaxUses, 3);
      expect(d.cacheConversation, isTrue);
    });
  });
}
