import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';
import 'fixtures.dart';

void main() {
  Resolution resolve(String text, {RuleBasedProviderResolver? r}) =>
      (r ?? conceptResolver()).resolve(UserInput(text: text));

  group('stripTrigger', () {
    final cases = <(String, String?)>[
      ('Claude, trag den Termin ein', 'trag den Termin ein'),
      ('Claude: trag den Termin ein', 'trag den Termin ein'),
      ('claude – Was ist los?', 'Was ist los?'),
      ('  Fable,   schreib ein Gedicht.', 'schreib ein Gedicht.'),
      ('Claude.', null),
      ('Claude!!!', null),
      ('Claude', null),
    ];
    for (final (text, expected) in cases) {
      test('„$text“ → ${expected ?? 'original'}', () {
        final r = resolve(text);
        expect(r.reason, 'Starkes Modell');
        expect(r.effectiveText, expected);
      });
    }

    test('rules without stripTrigger keep the text', () {
      expect(resolve('privat: trag das ein').effectiveText, isNull);
    });

    test('keyword trigger in the middle of a sentence', () {
      final rules = RuleSet(
        rules: [
          RoutingRule(
            id: 'k',
            name: 'Gründlich',
            condition: KeywordCondition(['denk gründlich nach']),
            target: claudeOpus,
            stripTrigger: true,
          ),
        ],
        defaultTarget: phalaSmall,
      );
      final r = resolve(
        'Bitte denk gründlich nach, was ich einpacken muss',
        r: conceptResolver(rules: rules),
      );
      expect(r.effectiveText, 'Bitte was ich einpacken muss');
    });

    test(
      'the model gets the stripped text, history keeps the original',
      () async {
        final (_, provider) = scripted('claude', [ScriptedTurn.text('Gern.')]);
        final profiles = [
          for (final p in conceptProfiles())
            p.id == 'claude'
                ? RoutingProfile(
                    id: p.id,
                    name: p.name,
                    privacy: p.privacy,
                    defaultModel: p.defaultModel,
                    provider: provider,
                  )
                : p,
        ];
        final (primary, _) = scripted('phala', const []);
        final h = Harness(
          primary: primary,
          resolver: conceptResolver(profiles: profiles),
        );
        final events = await h.run('Claude, trag den Termin ein');
        expect(events.first, isA<Routed>());
        expect((events.first as Routed).reason, 'Starkes Modell');
        expect(terminal(events), isA<AgentDone>());
        final sent = provider.requests.single.messages.last;
        expect(sent.role, Role.user);
        expect(
          sent.content.whereType<TextBlock>().single.text,
          'trag den Termin ein',
        );
        final stored = h.conversation.messages.first;
        expect(
          stored.content.whereType<TextBlock>().single.text,
          'Claude, trag den Termin ein',
        );
      },
    );

    test('empty rest: the model gets the original text', () async {
      final (_, provider) = scripted('claude', [ScriptedTurn.text('Ja?')]);
      final profiles = [
        for (final p in conceptProfiles())
          p.id == 'claude'
              ? RoutingProfile(
                  id: p.id,
                  name: p.name,
                  privacy: p.privacy,
                  defaultModel: p.defaultModel,
                  provider: provider,
                )
              : p,
      ];
      final (primary, _) = scripted('phala', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(profiles: profiles),
      );
      await h.run('Claude.');
      final sent = provider.requests.single.messages.last;
      expect(sent.content.whereType<TextBlock>().single.text, 'Claude.');
    });
  });

  group('escalation', () {
    test('walks the chain of the routed profile', () {
      final resolver = conceptResolver();
      final r0 = resolve('hallo', r: resolver);
      final r1 = resolver.escalate(r0, EscalationReason.providerError)!;
      expect((r1.profileId, r1.modelId), ('phala', 'glm-large'));
      expect(r1.reason, 'Eskalation: providerError');
      final r2 = resolver.escalate(r1, EscalationReason.noProgress)!;
      expect(r2.modelId, 'claude-sonnet');
      expect(r2.routeProfileId, 'phala');
      final r3 = resolver.escalate(r2, EscalationReason.noProgress)!;
      expect(r3.modelId, 'claude-opus');
      expect(resolver.escalate(r3, EscalationReason.noProgress), isNull);
    });

    test('a rule route uses its own profile chain', () {
      final resolver = conceptResolver();
      final r0 = resolve('Schreib die Notiz um', r: resolver);
      expect(r0.modelId, 'claude-sonnet');
      final r1 = resolver.escalate(r0, EscalationReason.modelGaveUp)!;
      expect(r1.modelId, 'claude-opus');
      expect(resolver.escalate(r1, EscalationReason.modelGaveUp), isNull);
    });

    test('a route without a chain cannot escalate', () {
      final resolver = conceptResolver();
      final r0 = resolve(
        'Wie spät?',
        r: conceptResolver(network: FixedNetworkStatus(NetworkState.offline)),
      );
      expect(r0.profileId, 'ollama');
      expect(resolver.escalate(r0, EscalationReason.providerError), isNull);
    });

    test('unavailable chain entries are skipped', () {
      final resolver = conceptResolver(
        profiles: conceptProfiles(disabled: {'claude'}),
      );
      final r1 = resolver.escalate(
        resolve('hallo', r: resolver),
        EscalationReason.providerError,
      )!;
      expect(r1.modelId, 'glm-large');
      expect(resolver.escalate(r1, EscalationReason.providerError), isNull);
    });

    test('privacy floor stays the same over several escalations', () {
      final rules = conceptRules(
        chains: {
          'phala': [claudeSonnet, ollama, mistral, claudeOpus],
        },
      );
      final resolver = conceptResolver(rules: rules);
      final r0 = resolve('privat: mein Kontostand', r: resolver);
      expect(r0.privacyFloor, PrivacyLevel.tee);
      // Claude (standard) is skipped in favour of Ollama (local).
      final r1 = resolver.escalate(r0, EscalationReason.providerError)!;
      expect(r1.profileId, 'ollama');
      expect(r1.privacyFloor, PrivacyLevel.tee);
      expect(r1.belowPrivacyFloor, isFalse);
      // Nothing compliant is left: the next target needs consent.
      final r2 = resolver.escalate(r1, EscalationReason.providerError)!;
      expect(r2.profileId, 'mistral');
      expect(r2.privacyFloor, PrivacyLevel.tee);
      expect(r2.belowPrivacyFloor, isTrue);
      final r3 = resolver.escalate(r2, EscalationReason.providerError)!;
      expect(r3.modelId, 'claude-opus');
      expect(r3.privacyFloor, PrivacyLevel.tee);
      expect(r3.belowPrivacyFloor, isTrue);
    });

    test('target below the floor needs confirmation in the agent', () async {
      final (_, phala) = scripted('phala', [
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
      ]);
      final (_, claude) = scripted('claude', [ScriptedTurn.text('Hier.')]);
      final profiles = [
        for (final p in conceptProfiles())
          RoutingProfile(
            id: p.id,
            name: p.name,
            privacy: p.privacy,
            defaultModel: p.defaultModel,
            provider: switch (p.id) {
              'phala' => phala,
              'claude' => claude,
              _ => p.provider,
            },
          ),
      ];
      final rules = conceptRules(
        chains: {
          'phala': [claudeSonnet],
        },
      );
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(rules: rules, profiles: profiles),
      );
      final asked = <EscalationConfirmationRequired>[];
      final events = await h.run(
        'privat: Kontostand',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            asked.add(e);
            e.respond(true);
          }
        },
      );
      expect(asked.single.toProfile, 'claude');
      expect(events.whereType<Escalated>().single.toProfile, 'claude');
      expect(terminal(events), isA<AgentDone>());
    });
  });

  group('„nochmal mit …“', () {
    final cases = <(String, RouteTarget?)>[
      ('nochmal mit Claude', claudeOpus),
      ('Noch mal mit Fable bitte', claudeOpus),
      ('Kannst du das nochmal mit Claude machen?', claudeOpus),
      ('nochmal mit Sonnet', claudeSonnet),
      ('Nochmal mit Claude API', claudeSonnet),
      ('nochmal mit Ollama Homeserver', ollama),
      ('encore avec Claude', claudeOpus),
      ('Encore une fois avec Mistral', mistral),
      ('again with claude, please', claudeOpus),
      ('try again with Phala GLM klein', phalaSmall),
      ('Bitte nochmal mit Claude', claudeOpus),
      ('Et maintenant encore avec Claude', claudeOpus),
      ('Can you do it again with Claude please', claudeOpus),
      // Dictated sentences: the phrase is not at the start.
      ('Schreib Anna: ich gehe morgen nochmal mit Claude ins Kino', null),
      ('Sag Tom, dass ich nochmal mit Fable rede', null),
      ('Envoie à Marie: on dîne encore avec Claude ce soir', null),
      ('Tell Bob I will go again with Claude tomorrow', null),
      // Too many words after the name.
      ('nochmal mit Claude ins Kino gehen', null),
      ('again with Claude to the cinema', null),
      ('nochmal mit Gefühl', null),
      ('nochmal', null),
      ('Claude, nochmal', null),
    ];
    for (final (text, target) in cases) {
      test('„$text“ → ${target ?? 'kein Ziel'}', () {
        final r = resolve(text);
        final t = r.requestedTarget;
        expect(
          t == null
              ? null
              : RouteTarget(profileId: t.profileId, modelId: t.modelId),
          target,
        );
      });
    }

    test('jumps to the named target instead of the next chain link', () {
      final resolver = conceptResolver();
      final r0 = resolve('nochmal mit Claude', r: resolver);
      expect(r0.profileId, 'phala');
      final r1 = resolver.escalate(r0, EscalationReason.userRequested)!;
      expect(r1.modelId, 'claude-opus');
      expect(r1.reason, 'Nutzerwunsch: Claude API');
      expect(r1.requestedTarget, isNull);
      // Further escalations continue on the routed profile's chain after
      // the named target: Opus is its last link.
      expect(resolver.escalate(r1, EscalationReason.providerError), isNull);
    });

    test('a named target outside the chain continues with the chain', () {
      final resolver = conceptResolver();
      final r0 = resolve('nochmal mit Ollama Homeserver', r: resolver);
      final r1 = resolver.escalate(r0, EscalationReason.userRequested)!;
      expect(r1.profileId, 'ollama');
      final r2 = resolver.escalate(r1, EscalationReason.providerError)!;
      expect(r2.modelId, 'glm-large');
    });

    test('other reasons ignore the named target', () {
      final resolver = conceptResolver();
      final r0 = resolve('nochmal mit Claude', r: resolver);
      final r1 = resolver.escalate(r0, EscalationReason.providerError)!;
      expect(r1.modelId, 'glm-large');
    });

    test('naming the current target retries on it (no next link)', () {
      final resolver = conceptResolver();
      final r0 = resolve('nochmal mit Phala GLM klein', r: resolver);
      final r1 = resolver.escalate(r0, EscalationReason.userRequested)!;
      expect((r1.profileId, r1.modelId), ('phala', 'glm-small'));
      expect(r1.reason, 'Nutzerwunsch: erneut');
    });

    test('same privacy check: below the floor needs consent', () {
      final resolver = conceptResolver();
      final r0 = resolve(
        'nochmal mit Claude',
        r: resolver,
      ).withPrivacyFloor(PrivacyLevel.tee);
      final r1 = resolver.escalate(r0, EscalationReason.userRequested)!;
      expect(r1.profileId, 'claude');
      expect(r1.privacyFloor, PrivacyLevel.tee);
      expect(r1.belowPrivacyFloor, isTrue);
    });

    test('the agent escalates without requestEscalation', () async {
      final (_, claude) = scripted('claude', [ScriptedTurn.text('Opus hier.')]);
      final (_, phala) = scripted('phala', const []);
      final profiles = [
        for (final p in conceptProfiles())
          RoutingProfile(
            id: p.id,
            name: p.name,
            privacy: p.privacy,
            defaultModel: p.defaultModel,
            provider: switch (p.id) {
              'phala' => phala,
              'claude' => claude,
              _ => p.provider,
            },
          ),
      ];
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(profiles: profiles),
      );
      final events = await h.run('nochmal mit Claude');
      final esc = events.whereType<Escalated>().single;
      expect((esc.fromProfile, esc.toProfile), ('phala', 'claude'));
      expect(esc.reason, EscalationReason.userRequested);
      expect(claude.requests.single.model, 'claude-opus');
      expect(phala.requests, isEmpty);
    });

    test('disabled rules and unavailable profiles give no names', () {
      final resolver = conceptResolver(
        profiles: conceptProfiles(unbuildable: {'mistral'}),
      );
      expect(
        resolve('nochmal mit Mistral', r: resolver).requestedTarget,
        isNull,
      );
      expect(
        resolve('again with think hard', r: resolver).requestedTarget,
        isNull,
      );
    });
  });

  group('rule availability', () {
    test('rules to a deleted or disabled profile are skipped and reported', () {
      final resolver = conceptResolver(
        profiles: [
          for (final p in conceptProfiles(disabled: {'ollama'}))
            if (p.id != 'claude') p,
        ],
      );
      expect(resolve('Claude, hallo', r: resolver).reason, 'Standard');
      expect(
        resolver.issues.map((i) => (i.kind, i.ruleId)),
        containsAll([
          (RuleSetIssueKind.profileMissing, 'strong'),
          (RuleSetIssueKind.profileMissing, 'notes'),
          (RuleSetIssueKind.profileDisabled, 'offline'),
        ]),
      );
      final offline = conceptResolver(
        profiles: conceptProfiles(disabled: {'ollama'}),
        network: FixedNetworkStatus(NetworkState.offline),
      );
      expect(resolve('Wetter?', r: offline).reason, 'Standard');
    });

    test('profiles without adapter are skipped when resolving', () {
      final resolver = conceptResolver(
        profiles: conceptProfiles(unbuildable: {'claude'}),
      );
      expect(resolve('Claude, hallo', r: resolver).reason, 'Standard');
    });

    test('an unavailable default target is an error', () {
      expect(
        () => conceptResolver(profiles: conceptProfiles(disabled: {'phala'})),
        throwsArgumentError,
      );
    });

    test('invalid regex rules are skipped, not a crash', () {
      final rules = conceptRules().copyWith(
        rules: [
          RoutingRule(
            id: 'broken',
            name: 'Kaputt',
            condition: RegexCondition('(claude'),
            target: claudeOpus,
          ),
        ],
      );
      final resolver = conceptResolver(rules: rules);
      expect(resolve('(claude', r: resolver).reason, 'Standard');
      expect(resolver.issues.single.kind, RuleSetIssueKind.invalidCondition);
    });

    test('time window rule with the injected clock', () {
      final clock = FixedClock(DateTime(2026, 10, 16, 23));
      final rules = conceptRules().copyWith(
        rules: [
          RoutingRule(
            id: 'night',
            name: 'Nachts lokal',
            condition: TimeWindowCondition(start: 22 * 60, end: 6 * 60),
            target: ollama,
          ),
        ],
      );
      final resolver = conceptResolver(rules: rules, clock: clock);
      expect(resolve('hallo', r: resolver).reason, 'Nachts lokal');
      clock.set(DateTime(2026, 10, 17, 6));
      expect(resolve('hallo', r: resolver).reason, 'Standard');
    });

    test('network rule follows the injected status', () {
      final network = FixedNetworkStatus();
      final resolver = conceptResolver(network: network);
      expect(resolve('Wetter?', r: resolver).reason, 'Standard');
      network.current = NetworkState.offline;
      expect(resolve('Wetter?', r: resolver).reason, 'Offline');
      expect(
        resolver.contextFor(UserInput(text: 'x')).network,
        NetworkState.offline,
      );
    });
  });

  group('migration of the global chain', () {
    test('becomes the chain of the default profile', () {
      final set = RuleSet.fromGlobalChain(
        defaultTarget: phalaSmall,
        globalChain: [claudeSonnet, phalaLarge, ollama, claudeOpus],
      );
      expect(set.rules, isEmpty);
      expect(set.defaultTarget, phalaSmall);
      expect(set.chains.keys, ['phala']);
      // The default profile itself and repeated profiles are dropped.
      expect(set.chainOf('phala'), [claudeSonnet, ollama]);
      expect(set.chainOf('claude'), isEmpty);
    });

    test('empty global chain gives no chains', () {
      final set = RuleSet.fromGlobalChain(
        defaultTarget: phalaSmall,
        globalChain: const [],
      );
      expect(set.chains, isEmpty);
    });

    test('behaves like the DefaultProviderResolver', () {
      final legacyChain = [claudeSonnet, ollama];
      final profiles = conceptProfiles();
      ProviderTarget build(RouteTarget t) {
        final p = profiles.firstWhere((p) => p.id == t.profileId);
        return ProviderTarget(
          profileId: t.profileId,
          modelId: t.modelId,
          provider: p.provider!,
          privacy: p.privacy,
        );
      }

      final old = DefaultProviderResolver(
        build(phalaSmall),
        legacyChain.map(build).toList(),
      );
      final migrated = conceptResolver(
        rules: RuleSet.fromGlobalChain(
          defaultTarget: phalaSmall,
          globalChain: legacyChain,
        ),
        profiles: profiles,
      );
      final input = UserInput(text: 'hallo');
      var a = old.resolve(input);
      var b = migrated.resolve(input);
      while (true) {
        expect((b.profileId, b.modelId), (a.profileId, a.modelId));
        final na = old.escalate(a, EscalationReason.providerError);
        final nb = migrated.escalate(b, EscalationReason.providerError);
        expect(nb == null, na == null);
        if (na == null || nb == null) break;
        a = na;
        b = nb;
      }
    });
  });

  test('value objects', () {
    final rule = conceptRules().rules.first;
    expect(rule.copyWith(), rule);
    expect(rule.copyWith().hashCode, rule.hashCode);
    expect(rule.copyWith(name: 'x'), isNot(rule));
    expect(rule.toString(), contains('claude/claude-opus'));
    expect(rule.isPrivate, isFalse);
    expect(conceptRules().rules[1].isPrivate, isTrue);
    expect(conceptRules(), conceptRules());
    expect(conceptRules().hashCode, conceptRules().hashCode);
    expect(conceptRules().copyWith(), conceptRules());
    expect(
      conceptRules().copyWith(defaultTarget: ollama),
      isNot(conceptRules()),
    );
    expect(phalaSmall.toString(), 'phala/glm-small');
    expect(conceptProfiles().first.toString(), contains('tee'));
    final r = resolve('Claude, hallo');
    expect(r.toString(), contains('Starkes Modell'));
  });
}
