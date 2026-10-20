import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';
import 'package:wendelin_providers/wendelin_providers.dart' show ModelPrice;

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
    expect(p.profile.options['thinking'], 'disabled');
  });

  test('jedes bepreiste Profil-Modell hat einen cacheRead (nie still 0)', () {
    // Fehlt cacheRead, rechnet der Katalog gecachte Eingabe-Tokens mit 0:
    // --max-cost zählte zu wenig. Ohne Cache-Rabatt gilt cacheRead == input.
    // Fake-Profile (Flachpreis ohne Cache) sind ausgenommen.
    final files = Directory('profiles')
        .listSync()
        .whereType<File>()
        .where((f) => !f.uri.pathSegments.last.startsWith('fake-'));
    for (final f in files) {
      final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      final models =
          ((json['catalog'] as Map<String, Object?>?)?['models']
              as Map<String, Object?>?) ??
          const {};
      for (final MapEntry(key: model, value: v) in models.entries) {
        final price = v! as Map<String, Object?>;
        expect(
          price['cacheRead'],
          isA<num>(),
          reason: '${f.path}: $model ohne cacheRead',
        );
        expect(
          price['cacheRead'] as num,
          lessThanOrEqualTo(price['input'] as num),
          reason: '${f.path}: $model',
        );
      }
    }
    final tinfoil = load('tinfoil-tee');
    for (final m in ['gpt-oss-120b', 'gemma4-31b']) {
      final price = tinfoil.catalog.lookup(m)!.price;
      expect(price.cacheRead, price.input, reason: m);
    }
  });

  test('Tinfoil: TEE-Profil mit Preisen der drei Modelle (2026-10-20)', () {
    final p = load('tinfoil-tee');
    expect(p.profile.privacy.name, 'tee');
    expect(p.profile.baseUrl, 'https://inference.tinfoil.sh/v1');
    final prices = {
      'gpt-oss-120b': (0.15, 0.6),
      'gemma4-31b': (0.4, 1.0),
      'deepseek-v4-1-flash': (0.65, 1.45),
    };
    for (final MapEntry(key: model, value: (input, output)) in prices.entries) {
      final entry = p.catalog.lookup(model);
      expect(entry, isNotNull, reason: model);
      final want = ModelPrice.usd(input: input, output: output);
      expect(
        (entry!.price.input, entry.price.output),
        (want.input, want.output),
        reason: model,
      );
    }
    expect(
      p.catalog.lookup('deepseek-v4-1-flash')!.price.cacheRead,
      ModelPrice.usd(input: 0, output: 0, cacheRead: 0.13).cacheRead,
    );
  });

  test('modelOptions gelten für das gewählte Modell, nicht für andere', () {
    final p = load('tinfoil-tee');
    expect(p.profile.options['reasoningEffort'], 'low');
    final gemma = p.withModel('gemma4-31b').profile.options;
    expect(gemma['extraBody'], {
      'chat_template_kwargs': {'enable_thinking': false},
    });
    expect(gemma, isNot(contains('reasoningEffort')));
    expect(gemma['toolsOnly'], isTrue);
    // Ohne Eintrag bleiben nur die Profil-Optionen.
    expect(p.withModel('llama3-3-70b').profile.options, {'toolsOnly': true});
  });

  test('modelOptions: extraBody wird mit dem des Profils zusammengeführt', () {
    final p = EvalProfile.parse('''{
      "id": "x", "name": "X", "type": "openaiCompatible",
      "baseUrl": "https://example.org/v1", "defaultModel": "a",
      "privacy": "standard", "authMethod": {"kind": "none"},
      "options": {"extraBody": {"seed": 1}},
      "modelOptions": {"a": {"extraBody": {"top_k": 5}}}
    }''');
    expect(p.profile.options['extraBody'], {'seed': 1, 'top_k': 5});
    expect(p.withModel('b').profile.options['extraBody'], {'seed': 1});
  });

  test('modelOptions: falsche Form wird abgelehnt', () {
    for (final bad in ['"x"', '{"a": 1}']) {
      expect(
        () => EvalProfile.parse('''{
          "id": "x", "name": "X", "type": "openaiCompatible",
          "baseUrl": "https://example.org/v1", "defaultModel": "a",
          "privacy": "standard", "authMethod": {"kind": "none"},
          "modelOptions": $bad
        }'''),
        throwsFormatException,
        reason: bad,
      );
    }
  });

  test('NEAR- und Phala-Modelle sind bepreist', () {
    for (final n in ['near-tee', 'phala-tee-small']) {
      final p = load(n);
      expect(p.catalog.lookup(p.profile.defaultModel), isNotNull, reason: n);
    }
    expect(load('openai-mini').catalog.lookup('gpt-5-mini'), isNotNull);
  });
}
