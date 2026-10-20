import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  EvalProfile load(String name) =>
      EvalProfile.parse(File('profiles/$name.json').readAsStringSync());

  test('alle Profile lesbar, ohne Keys, mit erwarteter Variable', () {
    const vars = {
      'claude-haiku': 'ANTHROPIC_API_KEY',
      'claude-sonnet': 'ANTHROPIC_API_KEY',
      'near-tee': 'NEAR_AI_API_KEY',
      'openai-mini': 'OPENAI_API_KEY',
      'phala-tee-small': 'PHALA_API_KEY',
      'tinfoil-tee': 'TINFOIL_API_KEY',
    };
    for (final e in vars.entries) {
      expect(load(e.key).apiKeyVariable, e.value, reason: e.key);
    }
  });

  test('Sonnet ist bepreist und läuft ohne Thinking', () {
    final p = load('claude-sonnet');
    expect(p.profile.defaultModel, 'claude-sonnet-5-5');
    expect(p.catalog.lookup('claude-sonnet-5-5'), isNotNull);
    expect(
      File('profiles/claude-sonnet.json').readAsStringSync(),
      isNot(contains('thinking')),
    );
  });

  test(
    'Tinfoil: TEE-Profil, Preise noch offen (fail-closed bei --max-cost)',
    () {
      final p = load('tinfoil-tee');
      expect(p.profile.privacy.name, 'tee');
      expect(p.profile.baseUrl, 'https://inference.tinfoil.sh/v1');
      expect(p.catalog.lookup(p.profile.defaultModel), isNull);
    },
  );

  test('NEAR- und Phala-Modelle sind bepreist', () {
    for (final n in ['near-tee', 'phala-tee-small']) {
      final p = load(n);
      expect(p.catalog.lookup(p.profile.defaultModel), isNotNull, reason: n);
    }
    expect(load('openai-mini').catalog.lookup('gpt-5-mini'), isNotNull);
  });
}
