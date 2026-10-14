// Texts of provider failures: reason in de/fr/en, never the raw exception
// text (K28: the run ends with the reason).

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  const raw = 'ROH-TEXT-api-key-sk-123';
  final errors = <ProviderException>[
    const NetworkException(raw),
    const ProviderTimeoutException(raw),
    const RateLimitException(raw),
    const ServerException(raw, statusCode: 500),
    const AuthException(raw),
    const InvalidRequestException(raw),
    const MalformedResponseException(raw),
    const AttestationFailedException(raw, stage: 'quote'),
  ];

  for (final error in errors) {
    test('${error.runtimeType}: own reason per language, no raw text', () {
      final texts = {
        for (final lang in ['de', 'fr', 'en', null, 'xx', 'fr-CH'])
          lang: AgentRunnerTexts.providerFailure(
            'Claude',
            error,
            language: lang,
          ),
      };
      for (final t in texts.values) {
        expect(t, contains('Claude'));
        expect(t, isNot(contains(raw)));
      }
      expect(texts[null], texts['de']);
      expect(texts['xx'], texts['de']);
      expect(texts['fr-CH'], texts['fr']);
      expect({texts['de'], texts['fr'], texts['en']}, hasLength(3));
    });
  }

  test('unavailable and not-sent texts exist in all languages', () {
    for (final reason in ['missing', 'disabled', 'incomplete']) {
      final t = {
        for (final lang in ['de', 'fr', 'en'])
          AgentRunnerTexts.targetUnavailable('X', reason, language: lang),
      };
      expect(t, hasLength(3));
    }
    expect({
      for (final lang in ['de', 'fr', 'en'])
        AgentRunnerTexts.notSent('X', language: lang),
    }, hasLength(3));
  });
}
