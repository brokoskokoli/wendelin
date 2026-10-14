@Tags(['live'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
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

/// Skips the running test without [key]. Inside the test (not `skip:`),
/// because `--run-skipped` – needed for the `live` tag – ignores `skip:`.
bool _skipWithout(String? key, String envKey) {
  if (key != null && key.isNotEmpty) return false;
  markTestSkipped('$envKey nicht gesetzt');
  return true;
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
      if (_skipWithout(key, envKey)) return;
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
      if (_skipWithout(key, envKey)) return;
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
  });
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

  // qwen/qwen-2.5-7b-instruct läuft laut /v1/models mit is_tee: true; das
  // prüft der folgende (kostenlose) Test, bevor die Chat-Anfragen laufen.
  final phalaKey = Platform.environment['PHALA_API_KEY'];
  test('Phala: Live-Modell ist ein TEE-Modell (is_tee)', () async {
    if (_skipWithout(phalaKey, 'PHALA_API_KEY')) return;
    final models = await OpenAiChatAdapter(
      baseUrl: Uri.parse('https://api.redpill.ai/v1'),
      credentials: Credentials.apiKey(phalaKey!, style: ApiKeyStyle.bearer),
      defaultModel: 'qwen/qwen-2.5-7b-instruct',
      options: const OpenAiOptions(teeModelsOnly: true),
    ).listModels();
    expect(models.map((m) => m.id), contains('qwen/qwen-2.5-7b-instruct'));
  });

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

  test('Phala: Anfrage geht nur über die gegen die Attestierung geprüfte '
      'TLS-Verbindung (WP61)', () async {
    if (_skipWithout(phalaKey, 'PHALA_API_KEY')) return;
    final provider = ProviderFactory.create(
      ProviderProfile(
        id: 'phala',
        name: 'Phala',
        type: ProviderType.openaiCompatible,
        baseUrl: 'https://api.redpill.ai/v1',
        defaultModel: 'qwen/qwen-2.5-7b-instruct',
        privacy: PrivacyLevel.tee,
        authMethod: const ApiKeyAuth('ref'),
        options: const {'attestation': 'phala'},
      ),
      (_) async => phalaKey!,
      // Quote signature chain is not checked here (fake crypto); the SPKI
      // hashing is the real one for X.509 DER.
      attestation: AttestationWiring(crypto: FakeAttestationCrypto()),
    ) as AttestedProvider;
    final events = await provider
        .chat(
          ChatRequest(
            systemPrompt: 'Antworte mit einem Wort.',
            messages: [Message.user('Sag Hallo.')],
            model: 'qwen/qwen-2.5-7b-instruct',
            maxTokens: 10,
          ),
        )
        .toList();
    _report('Phala (TLS-Pin)', 'qwen/qwen-2.5-7b-instruct', events);
    // The pin let the request through: Done, or HTTP 402 (the Phala key has
    // no credit at the moment; the factory maps 401/402/403 to
    // AuthException). Any other error, in particular a refused connection
    // (AttestationFailedException), fails.
    final last = events.last;
    expect(
      last is Done || (last is ErrorEvent && last.error is AuthException),
      isTrue,
      reason: '$last',
    );
    final tls = provider.lastSessionStages.firstWhere(
      (s) => s.stage == AttestationStage.tlsSpki,
    );
    expect(tls.outcome, StageOutcome.pass, reason: tls.detail);
  });
}
