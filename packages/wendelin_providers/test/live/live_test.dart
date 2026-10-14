@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/fakes.dart';
import 'package:wendelin_providers/src/tee/codec.dart';
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

/// Marks the running test as skipped if the provider answered with an
/// authorization error and [tolerateNoCredit] is set (the Phala key has no
/// credit at the moment: HTTP 402 is mapped to `AuthException`). Returns
/// whether it did. The test then proves nothing about the answer path.
bool _noCredit(List<ChatEvent> events, {required bool tolerateNoCredit}) {
  final last = events.last;
  if (tolerateNoCredit && last is ErrorEvent && last.error is AuthException) {
    // ignore: avoid_print
    print('KEIN BELEG: Anbieter antwortet mit Auth-/Guthabenfehler');
    markTestSkipped('kein Guthaben (HTTP 401/402/403)');
    return true;
  }
  return false;
}

void _liveSuite({
  required String name,
  required String envKey,
  required String model,
  required LlmProvider Function(String key) create,
  bool tolerateNoCredit = false,
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
      if (_noCredit(events, tolerateNoCredit: tolerateNoCredit)) return;
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
      if (_noCredit(events, tolerateNoCredit: tolerateNoCredit)) return;
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

  // google/gemma-4-31b-it läuft laut /v1/models mit is_tee: true; das
  // prüft der folgende (kostenlose) Test, bevor die Chat-Anfragen laufen.
  final phalaKey = Platform.environment['PHALA_API_KEY'];
  test('Phala: Live-Modell ist ein TEE-Modell (is_tee)', () async {
    if (_skipWithout(phalaKey, 'PHALA_API_KEY')) return;
    final models = await OpenAiChatAdapter(
      baseUrl: Uri.parse('https://api.redpill.ai/v1'),
      credentials: Credentials.apiKey(phalaKey!, style: ApiKeyStyle.bearer),
      defaultModel: _phalaModel,
      options: const OpenAiOptions(teeModelsOnly: true),
    ).listModels();
    expect(models.map((m) => m.id), contains(_phalaModel));
  });

  _liveSuite(
    name: 'Phala (E2EE v2)',
    envKey: 'PHALA_API_KEY',
    model: _phalaModel,
    // All Phala requests go through the attested provider: TLS pin and
    // end-to-end encryption are mandatory there. The quote signature chain
    // is not checked (fake crypto); the E2EE key comes from the real,
    // digest-bound keyset of the live attestation.
    create: _phalaProvider,
    tolerateNoCredit: true,
  );

  test(
    'Phala: Anfrage geht nur über die gegen die Attestierung geprüfte '
    'TLS-Verbindung (WP61) und ist Ende-zu-Ende verschlüsselt (WP62)',
    () async {
      if (_skipWithout(phalaKey, 'PHALA_API_KEY')) return;
      final provider = _phalaProvider(phalaKey!) as AttestedProvider;
      final events = await provider
          .chat(
            ChatRequest(
              systemPrompt: 'Antworte mit einem Wort.',
              messages: [Message.user('Sag Hallo.')],
              model: _phalaModel,
              maxTokens: 10,
            ),
          )
          .toList();
      _report('Phala (TLS-Pin, E2EE)', _phalaModel, events);
      // The pin let the request through: Done, or HTTP 402 (the Phala key has
      // no credit at the moment; the factory maps 401/402/403 to
      // AuthException). Any other error, in particular a refused connection
      // or a failed E2EE check (AttestationFailedException), fails.
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
      final key = provider.lastSessionStages.firstWhere(
        (s) => s.stage == AttestationStage.e2eeKey,
      );
      expect(key.outcome, StageOutcome.pass, reason: key.detail);
      if (last is Done) {
        expect(events.whereType<TextDelta>(), isNotEmpty);
      }
    },
  );

  // Evidence that the gateway really expects encrypted requests, in spite of
  // the missing credit: a correctly encrypted request and two broken ones
  // (cipher bound to another nonce, plain text) are told apart by the error
  // type. Prints only status codes and error types.
  test('Phala E2EE: Dienst unterscheidet richtig und falsch verschlüsselte '
      'Anfragen', () async {
    if (_skipWithout(phalaKey, 'PHALA_API_KEY')) return;
    final provider = _phalaProvider(phalaKey!) as AttestedProvider;
    expect(await provider.reattest().then((r) => r.status), isNotNull);
    final session = provider.session;
    if (session == null) {
      fail('Attestierung nicht grün: ${provider.lastSessionStages}');
    }
    final crypto = FakeAttestationCrypto();
    final random = Random.secure();
    String nonce() => AttestCodec.hex(
      Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
    );
    final body = {
      'model': _phalaModel,
      'messages': [
        {'role': 'user', 'content': 'Sag Hallo.'},
      ],
      'max_tokens': 5,
      'stream': false,
    };
    Future<(int, String)> post(
      Map<String, String> headers,
      String payload,
    ) async {
      final response = await http.post(
        Uri.parse('https://api.redpill.ai/v1/chat/completions'),
        headers: {
          ...headers,
          'Authorization': 'Bearer $phalaKey',
          'content-type': 'application/json',
        },
        body: payload,
      );
      String type;
      try {
        final error = (jsonDecode(response.body) as Map)['error'];
        type = '${error is Map ? error['type'] ?? error['code'] : error}';
      } on Object {
        type = '(kein JSON-Fehler)';
      }
      return (response.statusCode, type);
    }

    E2eeV2Wire wire() => E2eeV2Wire(
      crypto: crypto,
      key: session.e2eeKey!,
      model: _phalaModel,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      nonce: nonce(),
    );

    final good = wire();
    final goodResult = await post(good.headers, good.seal(body).wire);
    // AAD bound to another nonce than the header names.
    final skewed = wire();
    final skewedResult = await post({
      ...skewed.headers,
      'X-E2EE-Nonce': nonce(),
    }, skewed.seal(body).wire);
    // Valid headers, plain text content.
    final plain = wire();
    final plainResult = await post(plain.headers, jsonEncode(body));
    // ignore: avoid_print
    print(
      'E2EE-Beleg: richtig=$goodResult, falsche AAD=$skewedResult, '
      'Klartext=$plainResult',
    );
    expect(skewedResult.$2, 'e2ee_decryption_failed');
    expect(plainResult.$2, 'e2ee_decryption_failed');
    expect(goodResult.$2, isNot('e2ee_decryption_failed'));
  });
}

const _phalaModel = 'google/gemma-4-31b-it';

LlmProvider _phalaProvider(String key) => ProviderFactory.create(
  ProviderProfile(
    id: 'phala',
    name: 'Phala',
    type: ProviderType.openaiCompatible,
    baseUrl: 'https://api.redpill.ai/v1',
    defaultModel: _phalaModel,
    privacy: PrivacyLevel.tee,
    authMethod: const ApiKeyAuth('ref'),
    options: const {'attestation': 'phala'},
  ),
  (_) async => key,
  // Quote signature chain is not checked here (fake crypto); the SPKI
  // hashing is the real one for X.509 DER.
  attestation: AttestationWiring(crypto: FakeAttestationCrypto()),
);
