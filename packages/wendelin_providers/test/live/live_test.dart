@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

// Live-Tests gegen echte APIs, sparsam: kleinste Modelle, max. 200 Tokens,
// je eine Text- und eine Tool-Anfrage. Keys nur aus der Umgebung, nie
// ausgeben. Start:
//   set -a; . ~/.wendelin-live.env; set +a; dart test -t live --run-skipped

const _tool = ToolSpec(
  name: 'calendar__create',
  description: 'Legt einen Kalendertermin an.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': 'Titel'},
      'day': {'type': 'string', 'description': 'Tag, z. B. morgen'},
      'time': {'type': 'string', 'description': 'Uhrzeit HH:MM'},
    },
    'required': ['title', 'day', 'time'],
  },
);

final _costs = CostCalculator(ModelCatalog.builtIn());

void _report(String label, String model, List<ChatEvent> events) {
  final usage = events.whereType<UsageEvent>().fold(
    Usage.zero,
    (sum, e) => sum + e.usage,
  );
  final cost = _costs.costMicros(model, usage);
  // ignore: avoid_print
  print('$label ($model): $usage, Kosten: ${cost ?? '?'} µUSD');
}

void _liveSuite({
  required String name,
  required String envKey,
  required String model,
  required LlmProvider Function(String key) create,
}) {
  final key = Platform.environment[envKey];
  group(name, () {
    test('Textanfrage', () async {
      final events = await create(key!)
          .chat(
            ChatRequest(
              systemPrompt: 'Antworte in höchstens fünf Wörtern auf Deutsch.',
              messages: [Message.user('Sag hallo.')],
              model: model,
              maxTokens: 200,
            ),
          )
          .toList();
      _report('$name Text', model, events);
      expectWellFormedChatStream(events);
      expect(events.last, isA<Done>(), reason: '${events.last}');
      expect(
        events.whereType<TextDelta>().map((e) => e.text).join(),
        isNotEmpty,
      );
      expect(events.whereType<UsageEvent>(), isNotEmpty);
    });

    test('Tool-Anfrage', () async {
      final events = await create(key!)
          .chat(
            ChatRequest(
              systemPrompt: 'Du bist ein Sprachassistent. Nutze Tools.',
              messages: [Message.user('Trag mir morgen um 10 Tauchen ein.')],
              tools: const [_tool],
              model: model,
              maxTokens: 200,
            ),
          )
          .toList();
      _report('$name Tool', model, events);
      expectWellFormedChatStream(events);
      expect(
        events.last,
        const Done(StopReason.toolUse),
        reason: '${events.last}',
      );
      final call = events.whereType<ToolCallComplete>().first.call;
      expect(call.name, _tool.name);
      final args = call.tryDecodeArguments();
      expect(args, isNotNull);
      expect('${args!['title']}'.toLowerCase(), contains('tauch'));
    });
  }, skip: key == null || key.isEmpty ? '$envKey nicht gesetzt' : false);
}

void main() {
  _liveSuite(
    name: 'Anthropic',
    envKey: 'ANTHROPIC_API_KEY',
    model: 'claude-haiku-5-5',
    create: (key) => AnthropicMessagesAdapter(
      credentials: Credentials.apiKey(key, style: ApiKeyStyle.xApiKey),
      defaultModel: 'claude-haiku-5-5',
      options: const AnthropicOptions(reasoningEffort: 'low'),
    ),
  );

  final openAiBase = Platform.environment['OPENAI_BASE_URL'];
  _liveSuite(
    name: 'OpenAI',
    envKey: 'OPENAI_API_KEY',
    model: Platform.environment['OPENAI_MODEL'] ?? 'gpt-4.1-nano',
    create: (key) => OpenAiChatAdapter(
      baseUrl: Uri.parse(openAiBase ?? 'https://api.openai.com/v1'),
      credentials: Credentials.apiKey(key, style: ApiKeyStyle.bearer),
      defaultModel: 'gpt-4.1-nano',
      label: 'OpenAI',
    ),
  );

  _liveSuite(
    name: 'Phala',
    envKey: 'PHALA_API_KEY',
    model: 'qwen/qwen-2.5-7b-instruct',
    create: (key) => OpenAiChatAdapter(
      baseUrl: Uri.parse('https://api.redpill.ai/v1'),
      credentials: Credentials.apiKey(key, style: ApiKeyStyle.bearer),
      defaultModel: 'qwen/qwen-2.5-7b-instruct',
      label: 'Phala',
    ),
  );
}
