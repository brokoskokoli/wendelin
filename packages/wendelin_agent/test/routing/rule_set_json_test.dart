import 'dart:convert';
import 'dart:math';

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

import 'fixtures.dart';

/// Random condition trees for the round trip.
final class _Gen {
  _Gen(int seed) : _r = Random(seed);
  final Random _r;

  String word() => [
    'Claude',
    'privat',
    'denk gründlich nach',
    'encore',
    'Ärger',
    '"quoted"',
    r'back\slash',
    '',
  ][_r.nextInt(8)];

  List<String> words() => [for (var i = _r.nextInt(3); i >= 0; i--) word()];

  Condition condition(int depth) {
    final kind = _r.nextInt(depth > 0 ? 14 : 11);
    return switch (kind) {
      0 => KeywordCondition(words()),
      1 => PrefixCondition(words()),
      2 => RegexCondition(
        ['^a+', r'\d{2}', '(kaputt', 'x' * 201][_r.nextInt(4)],
      ),
      3 => LanguageCondition(['de', 'fr', 'en'].sublist(_r.nextInt(3))),
      4 => SttConfidenceCondition(_r.nextInt(100) / 100),
      5 => InputLengthCondition(_r.nextInt(1000)),
      6 => const HasImageCondition(),
      7 => NetworkCondition(NetworkState.values[_r.nextInt(3)]),
      8 => TimeWindowCondition(
        days: {for (var i = 0; i < _r.nextInt(8); i++) 1 + _r.nextInt(7)},
        start: _r.nextInt(1440),
        end: _r.nextInt(1440),
      ),
      9 => NeedsToolCondition(['obsidian.edit', 'calendar'][_r.nextInt(2)]),
      10 => _r.nextBool() ? PrivacyCondition() : PrivacyCondition(words()),
      11 => AndCondition([
        for (var i = _r.nextInt(3); i >= 0; i--) condition(depth - 1),
      ]),
      12 => OrCondition([
        for (var i = _r.nextInt(3); i >= 0; i--) condition(depth - 1),
      ]),
      _ => NotCondition(condition(depth - 1)),
    };
  }

  RouteTarget target() => [phalaSmall, claudeOpus, ollama][_r.nextInt(3)];

  RuleSet ruleSet() => RuleSet(
    rules: [
      for (var i = 0; i < _r.nextInt(6); i++)
        RoutingRule(
          id: 'r$i',
          name: 'Regel $i ${word()}',
          enabled: _r.nextBool(),
          condition: condition(3),
          target: target(),
          stripTrigger: _r.nextBool(),
          aliases: _r.nextBool() ? words() : const [],
        ),
    ],
    defaultTarget: target(),
    chains: {
      for (final id in ['phala', 'claude'])
        if (_r.nextBool())
          id: [for (var i = _r.nextInt(3); i >= 0; i--) target()],
    },
  );
}

void main() {
  final codec = RuleSetJson();

  test('round trip of the concept rules', () {
    final rules = conceptRules();
    final json = jsonEncode(codec.encode(rules));
    final back = codec.decode(jsonDecode(json));
    expect(back, rules);
    expect(jsonEncode(codec.encode(back)), json);
  });

  test('round trip is lossless for 300 generated rule sets', () {
    for (var seed = 0; seed < 300; seed++) {
      final rules = _Gen(seed).ruleSet();
      final json = jsonEncode(codec.encode(rules));
      final back = codec.decode(jsonDecode(json));
      expect(back, rules, reason: 'seed $seed: $json');
      expect(jsonEncode(codec.encode(back)), json, reason: 'seed $seed');
    }
  });

  test('every built-in type is registered and generated', () {
    final seen = <String>{};
    for (var seed = 0; seed < 300; seed++) {
      for (final r in _Gen(seed).ruleSet().rules) {
        seen.addAll(r.condition.all.map((c) => c.type));
      }
    }
    expect(seen, ConditionRegistry.standard.names.toSet());
  });

  test('export contains only ids, the schema version and no secrets', () {
    final json = codec.encode(conceptRules());
    expect(json['schemaVersion'], 1);
    expect(json['defaultTarget'], {
      'profileId': 'phala',
      'modelId': 'glm-small',
    });
    final text = jsonEncode(json);
    expect(text, isNot(contains('apiKey')));
    expect(text, isNot(contains('provider"')));
  });

  test('time windows are written as HH:MM, days sorted', () {
    final c = ConditionRegistry.standard.encode(
      TimeWindowCondition(days: {5, 1}, start: 22 * 60 + 5, end: 6 * 60),
    );
    expect(c, {
      'type': 'timeWindow',
      'days': [1, 5],
      'start': '22:05',
      'end': '06:00',
    });
  });

  test('optional fields have defaults', () {
    final set = codec.decode({
      'schemaVersion': 1,
      'defaultTarget': {'profileId': 'p', 'modelId': 'm'},
      'rules': [
        {
          'id': 'a',
          'name': 'A',
          'condition': {'type': 'privacy'},
          'target': {'profileId': 'p', 'modelId': 'm'},
        },
        {
          'id': 'b',
          'name': 'B',
          'condition': {'type': 'timeWindow', 'start': '1:00', 'end': '02:00'},
          'target': {'profileId': 'p', 'modelId': 'm'},
          'enabled': false,
        },
      ],
    });
    final a = set.rules.first;
    expect(a.enabled, isTrue);
    expect(a.stripTrigger, isFalse);
    expect(a.aliases, isEmpty);
    expect(a.condition, PrivacyCondition());
    expect(set.rules[1].condition, TimeWindowCondition(start: 60, end: 120));
    expect(set.rules[1].enabled, isFalse);
    expect(set.chains, isEmpty);
  });

  test('a broken regex is kept and reported, not a format error', () {
    final set = codec.decode({
      'schemaVersion': 1,
      'defaultTarget': {'profileId': 'phala', 'modelId': 'glm-small'},
      'rules': [
        {
          'id': 'x',
          'name': 'Kaputt',
          'condition': {'type': 'regex', 'pattern': '(claude'},
          'target': {'profileId': 'claude', 'modelId': 'claude-opus'},
        },
      ],
    });
    final issues = validateRuleSet(set, {
      for (final p in conceptProfiles()) p.id: p,
    });
    expect(issues.single.kind, RuleSetIssueKind.invalidCondition);
    expect(issues.single.message, contains('Ungültiger regulärer Ausdruck'));
  });

  group('errors', () {
    Map<String, Object?> withRule(Map<String, Object?> condition) => {
      'schemaVersion': 1,
      'defaultTarget': {'profileId': 'p', 'modelId': 'm'},
      'rules': [
        {
          'id': 'a',
          'name': 'A',
          'condition': condition,
          'target': {'profileId': 'p', 'modelId': 'm'},
        },
      ],
    };

    final cases = <(String, Object?, String)>[
      ('not an object', [], r'$: Objekt erwartet.'),
      ('missing version', <String, Object?>{}, r'$.schemaVersion: fehlt.'),
      (
        'newer schema',
        {'schemaVersion': 2},
        'Schema-Version 2 wird nicht unterstützt (erwartet: 1).',
      ),
      (
        'missing default target',
        {'schemaVersion': 1},
        r'$.defaultTarget: fehlt.',
      ),
      (
        'missing model id',
        {
          'schemaVersion': 1,
          'defaultTarget': {'profileId': 'p'},
        },
        r'$.defaultTarget.modelId: fehlt.',
      ),
      (
        'unknown condition type',
        withRule({'type': 'mondphase'}),
        'Unbekannter Bedingungstyp „mondphase“ (\$.rules[0].condition).',
      ),
      (
        'missing condition type',
        withRule({'words': <Object?>[]}),
        r'$.rules[0].condition.type: fehlt.',
      ),
      (
        'missing words',
        withRule({'type': 'keyword'}),
        r'$.rules[0].condition.words: fehlt.',
      ),
      (
        'words not a list',
        withRule({'type': 'keyword', 'words': 'Claude'}),
        r'$.rules[0].condition.words: Liste erwartet.',
      ),
      (
        'word not a string',
        withRule({
          'type': 'prefix',
          'words': [1],
        }),
        r'$.rules[0].condition.words[0]: Text erwartet.',
      ),
      (
        'nested unknown type',
        withRule({
          'type': 'and',
          'conditions': [
            {
              'type': 'not',
              'condition': {'type': 'x'},
            },
          ],
        }),
        r'$.rules[0].condition.conditions[0].condition)',
      ),
      (
        'bad network state',
        withRule({'type': 'network', 'state': 'wlan'}),
        '„wlan“ unbekannt, erlaubt: offline, online, metered.',
      ),
      (
        'bad time',
        withRule({'type': 'timeWindow', 'start': '25:00', 'end': '01:00'}),
        r'$.rules[0].condition.start: Uhrzeit HH:MM erwartet.',
      ),
      (
        'time not HH:MM',
        withRule({'type': 'timeWindow', 'start': 'abends', 'end': '01:00'}),
        'Uhrzeit HH:MM erwartet.',
      ),
      (
        'fractional length',
        withRule({'type': 'inputLength', 'above': 1.5}),
        r'$.rules[0].condition.above: ganze Zahl erwartet.',
      ),
      (
        'confidence not a number',
        withRule({'type': 'sttConfidence', 'below': 'hoch'}),
        r'$.rules[0].condition.below: Zahl erwartet.',
      ),
      (
        'enabled not a bool',
        {
          'schemaVersion': 1,
          'defaultTarget': {'profileId': 'p', 'modelId': 'm'},
          'rules': [
            {
              'id': 'a',
              'name': 'A',
              'enabled': 'ja',
              'condition': {'type': 'hasImage'},
              'target': {'profileId': 'p', 'modelId': 'm'},
            },
          ],
        },
        r'$.rules[0].enabled: true/false erwartet.',
      ),
      (
        'chains not an object',
        {
          'schemaVersion': 1,
          'defaultTarget': {'profileId': 'p', 'modelId': 'm'},
          'chains': <Object?>[],
        },
        r'$.chains: Objekt erwartet.',
      ),
      (
        'chain entry not an object',
        {
          'schemaVersion': 1,
          'defaultTarget': {'profileId': 'p', 'modelId': 'm'},
          'chains': {
            'p': ['claude'],
          },
        },
        r'$.chains.p[0]: Objekt erwartet.',
      ),
    ];
    for (final (name, json, message) in cases) {
      test(name, () {
        expect(
          () => codec.decode(json),
          throwsA(
            isA<RuleSetFormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }

    test('whole-number doubles are accepted', () {
      final set = codec.decode(withRule({'type': 'inputLength', 'above': 3.0}));
      expect(set.rules.single.condition, const InputLengthCondition(3));
    });
  });

  group('registry', () {
    test('custom types extend the registry without touching the codec', () {
      final hasImage = ConditionType(
        'bild',
        (_, _) => const HasImageCondition(),
        (_, _) => const {},
      );
      final registry = ConditionRegistry([...standardConditionTypes, hasImage]);
      expect(registry.names, contains('bild'));
      expect(registry.decode({'type': 'bild'}), const HasImageCondition());
    });

    test('encoding an unregistered type fails', () {
      final registry = ConditionRegistry(const []);
      expect(
        () => registry.encode(const HasImageCondition()),
        throwsArgumentError,
      );
    });
  });
}
