import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

String _json(Map<String, Object?> extra) => jsonEncode({
  'id': 'p',
  'name': 'P',
  'type': 'openaiCompatible',
  'baseUrl': 'https://api.openai.com/v1',
  'defaultModel': 'gpt-5-mini',
  'privacy': 'standard',
  'authMethod': {'kind': 'apiKey', 'secretRef': 'OPENAI_API_KEY'},
  ...extra,
});

void main() {
  test('liest Profil mit Eval-Schlüsseln', () {
    final p = EvalProfile.parse(
      _json({
        'escalationModels': ['gpt-5'],
        'script': 's.yaml',
        'catalog': {
          'models': {
            'gpt-5-mini': {'input': 1.0, 'output': 2.0},
          },
        },
      }),
    );
    expect(p.profile.id, 'p');
    expect(p.script, 's.yaml');
    expect(p.apiKeyVariable, 'OPENAI_API_KEY');
    final cost = p.costEstimator.estimateMicros(
      profileId: 'p',
      modelId: 'gpt-5-mini',
      usage: const Usage(inputTokens: 1000000, outputTokens: 1000000),
    );
    expect(cost, 3000000);
    final other = p.withModel('gpt-5-nano');
    expect(other.profile.defaultModel, 'gpt-5-nano');
  });

  test('Key-Variable je nach Typ', () {
    String? v(Map<String, Object?> extra) =>
        EvalProfile.parse(_json(extra)).apiKeyVariable;
    expect(
      v({
        'authMethod': {'kind': 'apiKey', 'secretRef': 'claude-key'},
        'type': 'anthropic',
      }),
      'ANTHROPIC_API_KEY',
    );
    expect(
      v({
        'authMethod': {'kind': 'apiKey', 'secretRef': 'phala'},
        'baseUrl': 'https://api.redpill.ai/v1',
      }),
      'PHALA_API_KEY',
    );
    expect(
      v({
        'authMethod': {'kind': 'apiKey', 'secretRef': 'x'},
      }),
      'OPENAI_API_KEY',
    );
    expect(
      v({
        'authMethod': {'kind': 'apiKey', 'secretRef': 'MY_KEY'},
      }),
      'MY_KEY',
    );
    expect(
      v({
        'authMethod': {'kind': 'none'},
      }),
      isNull,
    );
    expect(v({'type': 'fake'}), isNull);
  });

  test('ungültige Profile und Profile mit Schlüsseln', () {
    for (final bad in [
      'kein json',
      '[]',
      _json({'script': 3}),
      _json({
        'catalog': {'models': 1},
      }),
      _json({'apiKey': 'abc'}),
      _json({
        'options': {'key': 'abc'},
      }),
      _json({
        'extraHeaders': {
          'X-Test':
              'sk-'
              'abcdefghijklmnopqrstuvwx',
        },
      }),
      _json({
        'options': {
          'list': [
            'sk-'
                'ant-abcdefghijklmnopqrstuvwx',
          ],
        },
      }),
      _json({'privacy': 'geheim'}),
    ]) {
      expect(() => EvalProfile.parse(bad), throwsFormatException, reason: bad);
    }
  });

  test('strengere Prüfung auf Geheimnisse (Review #6)', () {
    const key =
        'sk-'
        'ant-abcdefghijklmnopqrstuvwx';
    for (final bad in [
      _json({
        'options': {'note': 'Bearer $key'},
      }),
      _json({
        'extraHeaders': {'Authorization': 'Bearer abc'},
      }),
      _json({
        'extraHeaders': {'X-Api-Key': 'abc'},
      }),
      _json({
        'extraHeaders': {'X-Session': 'Bearer abc'},
      }),
      _json({
        'extraHeaders': {'X-Custom': 'a1b2c3d4e5f6g7h8i9j0k1l2m3'},
      }),
      _json({
        'options': {'accessToken': 'abc'},
      }),
      _json({
        'options': {'password': 'abc'},
      }),
      _json({
        'options': {'client_secret': 'abc'},
      }),
      _json({
        'options': {'enableServerWebSearch': true},
      }),
    ]) {
      expect(() => EvalProfile.parse(bad), throwsFormatException, reason: bad);
    }
    // Erlaubt: Referenzen, harmlose Header und Optionen mit „tokens“.
    final ok = EvalProfile.parse(
      _json({
        'extraHeaders': {'X-Title': 'Wendelin Evals'},
        'options': {
          'maxTokensField': 'max_tokens',
          'enableServerWebSearch': false,
        },
        'authMethod': {'kind': 'apiKey', 'secretRef': 'OPENAI_API_KEY'},
      }),
    );
    expect(ok.profile.extraHeaders, {'X-Title': 'Wendelin Evals'});
  });

  test('harmlose Header mit Bindestrich-Wörtern sind erlaubt', () {
    final ok = EvalProfile.parse(
      _json({
        'type': 'anthropic',
        'extraHeaders': {
          'anthropic-beta': 'interleaved-thinking-2025-05-14',
          'anthropic-version': '2023-06-01',
          'HTTP-Referer': 'https://github.com/brokoskokoli/wendelin',
          'X-Feature': 'fine-grained-tool-streaming-2025-05-14',
        },
      }),
    );
    expect(
      ok.profile.extraHeaders['anthropic-beta'],
      'interleaved-thinking-2025-05-14',
    );
    // Ein langer Zufallswert ohne Trenner bleibt verdächtig.
    expect(
      () => EvalProfile.parse(
        _json({
          'extraHeaders': {'X-Custom': 'a1b2c3d4e5f6g7h8i9j0k1l2m3'},
        }),
      ),
      throwsFormatException,
    );
  });

  test('Beispielprofile im Repo sind gültig und enthalten keine Keys', () {
    for (final (file, variable) in [
      ('profiles/claude-haiku.json', 'ANTHROPIC_API_KEY'),
      ('profiles/openai-mini.json', 'OPENAI_API_KEY'),
      ('profiles/phala-tee-small.json', 'PHALA_API_KEY'),
      ('profiles/fake-demo.json', null),
    ]) {
      final p = EvalProfile.parse(File(file).readAsStringSync());
      expect(p.apiKeyVariable, variable, reason: file);
    }
  });
}
