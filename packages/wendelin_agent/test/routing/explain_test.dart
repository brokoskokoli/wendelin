import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'fixtures.dart';

void main() {
  final profiles = {
    for (final p in conceptProfiles(disabled: {'ollama'})) p.id: p,
  };
  final rules = conceptRules().copyWith(
    rules: [
      ...conceptRules().rules,
      RoutingRule(
        id: 'regex',
        name: 'Kaputt',
        condition: RegexCondition('(wetter'),
        target: claudeOpus,
      ),
      RoutingRule(
        id: 'gone',
        name: 'Gelöschtes Profil',
        condition: KeywordCondition(['wetter']),
        target: const RouteTarget(profileId: 'weg', modelId: 'm'),
      ),
      RoutingRule(
        id: 'weather',
        name: 'Wetter',
        condition: KeywordCondition(['wetter']),
        target: mistral,
      ),
    ],
  );

  const d = SkipReason.disabled;
  const n = SkipReason.noMatch;
  const i = SkipReason.invalid;
  const m = SkipReason.profileMissing;
  const off = SkipReason.profileDisabled;

  final cases = <(String, NetworkState, String, List<(String, SkipReason)>)>[
    ('Claude, hallo', NetworkState.online, 'Starkes Modell', []),
    ('privat', NetworkState.online, 'Privat', [('strong', n)]),
    (
      'Wetter?',
      NetworkState.offline,
      'Wetter',
      [
        ('strong', n),
        ('private', n),
        ('offline', off),
        ('notes', n),
        ('think', d),
        ('regex', i),
        ('gone', m),
      ],
    ),
    (
      'hallo',
      NetworkState.online,
      'Standard',
      [
        ('strong', n),
        ('private', n),
        ('offline', off),
        ('notes', n),
        ('think', d),
        ('regex', i),
        ('gone', m),
        ('weather', n),
      ],
    ),
  ];

  for (final (text, net, winner, skipped) in cases) {
    test('„$text“ ${net.name} → $winner, skipped $skipped', () {
      final decision = explain(
        rules,
        ctxFor(text, network: net, matcher: KeywordToolCategoryMatcher()),
        profiles: profiles,
      );
      expect(decision.reason, winner);
      expect(
        decision.skipped.map((s) => (s.rule.id, s.reason)).toList(),
        skipped,
      );
    });
  }

  test('details and targets', () {
    final decision = explain(rules, ctxFor('hallo'), profiles: profiles);
    expect(decision.rule, isNull);
    expect(decision.target, phalaSmall);
    expect(decision.private, isFalse);
    final invalid = decision.skipped.firstWhere((s) => s.reason == i);
    expect(invalid.detail, startsWith('Ungültiger regulärer Ausdruck'));
    expect(invalid.toString(), contains('Kaputt'));
    expect(decision.toString(), contains('Standard'));

    final strong = explain(rules, ctxFor('Claude, trag ein'));
    expect(strong.rule!.id, 'strong');
    expect(strong.target, claudeOpus);
    expect(strong.effectiveText, 'trag ein');
    expect(explain(rules, ctxFor('privat')).private, isTrue);
  });

  test('without profiles no profile checks', () {
    final decision = explain(
      rules,
      ctxFor('Wetter?', network: NetworkState.offline),
    );
    expect(decision.reason, 'Offline');
  });

  group('validateRuleSet', () {
    test('concept rules with all profiles are clean', () {
      expect(
        validateRuleSet(conceptRules(), {
          for (final p in conceptProfiles()) p.id: p,
        }),
        isEmpty,
      );
    });

    test('reports every kind of issue', () {
      final set = RuleSet(
        rules: [
          RoutingRule(
            id: 'a',
            name: 'Privat zu Claude',
            condition: OrCondition([
              PrivacyCondition(),
              const HasImageCondition(),
            ]),
            target: claudeOpus,
          ),
          RoutingRule(
            id: 'a',
            name: 'Doppelt',
            condition: RegexCondition('x' * 201),
            target: const RouteTarget(profileId: 'weg', modelId: 'm'),
          ),
          RoutingRule(
            id: 'b',
            name: 'Privat EU',
            condition: PrivacyCondition(),
            target: mistral,
          ),
          RoutingRule(
            id: 'c',
            name: 'Privat lokal',
            condition: PrivacyCondition(),
            target: ollama,
          ),
          RoutingRule(
            id: 'd',
            name: 'Nicht privat',
            condition: NotCondition(PrivacyCondition()),
            target: claudeOpus,
          ),
        ],
        defaultTarget: const RouteTarget(profileId: 'aus', modelId: 'm'),
      );
      final profiles = {
        for (final p in conceptProfiles(disabled: {'ollama'})) p.id: p,
      };
      final issues = validateRuleSet(set, profiles);
      expect(issues.map((i) => (i.kind, i.ruleId, i.profileId)).toList(), [
        (RuleSetIssueKind.privacyTargetTooWeak, 'a', 'claude'),
        (RuleSetIssueKind.duplicateRuleId, 'a', null),
        (RuleSetIssueKind.invalidCondition, 'a', null),
        (RuleSetIssueKind.profileMissing, 'a', 'weg'),
        (RuleSetIssueKind.privacyTargetTooWeak, 'b', 'mistral'),
        (RuleSetIssueKind.profileDisabled, 'c', 'ollama'),
        (RuleSetIssueKind.defaultTargetUnavailable, null, 'aus'),
      ]);
      expect(issues.first.message, contains('weder TEE noch lokal'));
      expect(issues[2].message, contains('200'));
      expect(issues.first, issues.first);
      expect(issues.first.hashCode, issues.first.hashCode);
      expect(issues.first, isNot(issues[4]));
      expect(issues.first.toString(), contains('privacyTargetTooWeak'));
    });

    test('a private TEE or local target is fine', () {
      final set = RuleSet(
        rules: [
          RoutingRule(
            id: 'p',
            name: 'Privat',
            condition: PrivacyCondition(),
            target: phalaSmall,
          ),
        ],
        defaultTarget: phalaSmall,
      );
      expect(
        validateRuleSet(set, {for (final p in conceptProfiles()) p.id: p}),
        isEmpty,
      );
      expect(PrivacyLevel.local.isAtLeast(PrivacyLevel.tee), isTrue);
    });
  });
}
