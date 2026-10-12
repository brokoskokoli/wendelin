import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/src/common/redactor.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../support/fake_server.dart';
import '../support/sample_conversation.dart';

/// Unusual key shape on purpose: no known prefix, so only the "known
/// secret" redaction can catch it.
const _key = 'Zq9-geheimer-Schluessel-4711-xyz';

/// Answers that echo the key back in every place a server might.
List<FakeResponse> _echoingResponses() => [
  const FakeResponse.json(
    401,
    '{"error":{"message":"Incorrect API key provided: $_key","type":"x"}}',
  ),
  const FakeResponse.json(
    429,
    '{"error":{"message":"limit for key $_key"}}',
    headers: {'retry-after': '1'},
  ),
  const FakeResponse.json(500, 'interner Fehler mit $_key im Klartext'),
  const FakeResponse.sse(
    'data: {"error":{"message":"stream error $_key"}}\n\n',
  ),
  const FakeResponse.sse(
    'event: error\ndata: {"type":"error","error":{"type":"api_error",'
    '"message":"boom $_key"}}\n\n',
  ),
  FakeResponse.fail(http.ClientException('connect failed for $_key')),
  FakeResponse.fail(Exception('irgendwas mit $_key')),
];

void main() {
  group('Key taucht nie in Fehlern, toString oder Logs auf', () {
    for (final kind in ['anthropic', 'openai']) {
      for (final (i, response) in _echoingResponses().indexed) {
        test('$kind, Antwort $i', () async {
          final lines = <String>[];
          final server = FakeServer([response]);
          final settings = HttpSettings(log: lines.add);
          final LlmProvider provider = kind == 'anthropic'
              ? AnthropicMessagesAdapter(
                  credentials: Credentials.apiKey(
                    _key,
                    style: ApiKeyStyle.xApiKey,
                  ),
                  defaultModel: 'm',
                  client: server.client,
                  settings: settings,
                )
              : OpenAiChatAdapter(
                  baseUrl: Uri.parse('https://example.test/v1'),
                  credentials: Credentials.apiKey(
                    _key,
                    style: ApiKeyStyle.bearer,
                  ),
                  defaultModel: 'm',
                  client: server.client,
                  settings: settings,
                );
          final events = await provider.chat(sampleRequest()).toList();
          final error = (events.last as ErrorEvent).error;
          // The request really carried the key ...
          expect(server.requests.single.headers.values.join(), contains(_key));
          // ... but nothing user- or log-facing does.
          for (final text in [
            error.message,
            error.toString(),
            events.last.toString(),
            provider.toString(),
            ...lines,
          ]) {
            expect(text, isNot(contains(_key)));
          }
          // (Anthropic ignores the OpenAI-style error chunk, answer 3, and
          // then reports a premature end without any server text.)
          if (!(kind == 'anthropic' && i == 3)) {
            expect(error.message, contains('***'));
          }
        });
      }

      test('$kind: listModels-Fehler ohne Key', () async {
        final server = FakeServer([
          const FakeResponse.json(
            403,
            '{"error":{"message":"forbidden $_key"}}',
          ),
        ]);
        final provider = kind == 'anthropic'
            ? AnthropicMessagesAdapter(
                credentials: Credentials.apiKey(
                  _key,
                  style: ApiKeyStyle.xApiKey,
                ),
                defaultModel: 'm',
                client: server.client,
              ) as LlmProvider
            : OpenAiChatAdapter(
                baseUrl: Uri.parse('https://example.test/v1'),
                credentials: Credentials.apiKey(
                  _key,
                  style: ApiKeyStyle.bearer,
                ),
                defaultModel: 'm',
                client: server.client,
              );
        try {
          await provider.listModels();
          fail('AuthException erwartet');
        } on AuthException catch (e) {
          expect(e.toString(), isNot(contains(_key)));
        }
        final health = await ProviderFactory.create(
          ProviderProfile(
            id: 'p',
            name: 'P',
            type: kind == 'anthropic'
                ? ProviderType.anthropic
                : ProviderType.openaiCompatible,
            baseUrl: 'https://example.test/v1',
            defaultModel: 'm',
            privacy: PrivacyLevel.standard,
            authMethod: const ApiKeyAuth('ref'),
          ),
          (_) async => _key,
          client: FakeServer([
            const FakeResponse.json(401, '{"error":{"message":"bad $_key"}}'),
          ]).client,
        ).test();
        expect(health.ok, isFalse);
        expect(health.message, isNot(contains(_key)));
        expect(health.toString(), isNot(contains(_key)));
      });
    }
  });

  group('Redactor', () {
    test('ersetzt bekannte Secrets und Key-Muster', () {
      final r = Redactor()..addSecret('mein-geheimnis');
      expect(r.apply('x mein-geheimnis y'), 'x *** y');
      expect(r.apply('key sk-ant-api03-abcdefghijkl'), 'key ***');
      expect(
        r.apply('Authorization: Bearer abcdefghijklmnop'),
        contains('***'),
      );
      expect(r.apply('Bearer abcdefghijklmnop'), 'Bearer ***');
      expect(r.apply('"api_key": "abcdefghijk"'), '"api_key": "***"');
      expect(r.apply('x-api-key=abcdefghijk'), 'x-api-key=***');
      expect(
        r.apply('harmloser Text mit 12 Tokens'),
        'harmloser Text mit 12 Tokens',
      );
    });

    test('zu kurze Secrets werden nicht registriert', () {
      final r = Redactor()..addSecret('abc');
      expect(r.apply('abc abc'), 'abc abc');
    });

    test('redact behält Typ und Zusatzfelder', () {
      final r = Redactor()..addSecret('geheimnis1');
      const msg = 'm geheimnis1';
      final cases = <ProviderException>[
        const AuthException(msg),
        const RateLimitException(msg, retryAfter: Duration(seconds: 3)),
        const ProviderTimeoutException(msg),
        const NetworkException(msg),
        const ServerException(msg, statusCode: 503),
        const InvalidRequestException(msg),
        const CancelledException(msg),
        const MalformedResponseException(msg),
      ];
      for (final e in cases) {
        final red = r.redact(e);
        expect(red.runtimeType, e.runtimeType);
        expect(red.message, 'm ***');
      }
      expect(
        (r.redact(cases[1]) as RateLimitException).retryAfter,
        const Duration(seconds: 3),
      );
      expect((r.redact(cases[4]) as ServerException).statusCode, 503);
      const clean = AuthException('sauber');
      expect(identical(r.redact(clean), clean), isTrue);
    });
  });
}
