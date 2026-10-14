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

  group('no automatic escalation (K28)', () {
    test('without a named target there is nothing to escalate to', () {
      final resolver = conceptResolver();
      for (final text in ['hallo', 'Schreib die Notiz um', 'privat: x']) {
        final r0 = resolve(text, r: resolver);
        expect(
          resolver.escalate(r0, EscalationReason.userRequested),
          isNull,
          reason: text,
        );
      }
      final offline = conceptResolver(
        network: FixedNetworkStatus(NetworkState.offline),
      );
      expect(
        offline.escalate(
          resolve('Wie spät?', r: offline),
          EscalationReason.userRequested,
        ),
        isNull,
      );
    });

    test('an error of the routed target never reaches another one', () async {
      final (_, phala) = scripted('phala', [
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
      ]);
      final (_, claude) = scripted('claude', [ScriptedTurn.text('nie')]);
      final (_, ollama) = scripted('ollama', [ScriptedTurn.text('nie')]);
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
              'ollama' => ollama,
              _ => p.provider,
            },
          ),
      ];
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(profiles: profiles),
      );
      for (final text in ['hallo', 'privat: Kontostand']) {
        final events = await h.run(text);
        expect(events.whereType<Escalated>(), isEmpty, reason: text);
        expect(
          events.whereType<EscalationConfirmationRequired>(),
          isEmpty,
          reason: text,
        );
        expect(
          (terminal(events) as AgentFailed).error,
          AgentErrorKind.provider,
        );
        expect(
          (terminal(events) as AgentFailed).message,
          startsWith('Phala'),
          reason: text,
        );
      }
      expect(claude.requests, isEmpty);
      expect(ollama.requests, isEmpty);
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

    test('jumps to the named target', () {
      final resolver = conceptResolver();
      final r0 = resolve('nochmal mit Claude', r: resolver);
      expect(r0.profileId, 'phala');
      final r1 = resolver.escalate(r0, EscalationReason.userRequested)!;
      expect(r1.modelId, 'claude-opus');
      expect(r1.reason, 'Nutzerwunsch: Claude API');
      expect(r1.requestedTarget, isNull);
      // Nothing follows on its own: no further target.
      expect(resolver.escalate(r1, EscalationReason.userRequested), isNull);
    });

    test('naming the current target retries on it', () {
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

  group('named but unavailable targets fail, never route elsewhere (K28)', () {
    final cases = <(String, RoutingProfile Function(RoutingProfile), String)>[
      (
        'disabled',
        (p) => RoutingProfile(
          id: p.id,
          name: p.name,
          privacy: p.privacy,
          defaultModel: p.defaultModel,
          enabled: false,
          provider: p.provider,
          aliases: p.aliases,
        ),
        'disabled',
      ),
      (
        'incomplete',
        (p) => RoutingProfile(
          id: p.id,
          name: p.name,
          privacy: p.privacy,
          defaultModel: p.defaultModel,
          aliases: p.aliases,
        ),
        'incomplete',
      ),
    ];
    for (final (name, change, reason) in cases) {
      RuleBasedProviderResolver without() => conceptResolver(
        profiles: [
          for (final p in conceptProfiles())
            if (p.id == 'claude') change(p) else p,
        ],
      );

      test('$name: „nochmal mit Claude API“', () {
        final r = resolve('nochmal mit Claude API', r: without());
        expect(r.unavailable?.name, 'Claude API');
        expect(r.unavailable?.reason, reason);
        expect(r.requestedTarget, isNull);
      });

      test('$name: alias „nochmal mit Sonnet“', () {
        final r = resolve('nochmal mit Sonnet', r: without());
        expect(r.unavailable?.reason, reason);
      });

      test('$name: prefix „Claude, …“', () {
        final r = resolve('Claude, trag den Termin ein', r: without());
        expect(r.unavailable?.reason, reason);
      });
    }

    test('available targets and plain text stay unaffected', () {
      expect(resolve('nochmal mit Claude API').unavailable, isNull);
      expect(resolve('Claude, hallo').unavailable, isNull);
      expect(resolve('Wie ist das Wetter?').unavailable, isNull);
    });

    test('a privacy keyword with an unavailable target is no choice', () {
      final r = conceptResolver(
        rules: conceptRules().copyWith(defaultTarget: claudeSonnet),
        profiles: conceptProfiles(disabled: {'phala'}),
      ).resolve(UserInput(text: 'privat: x'));
      expect(r.unavailable, isNull);
    });

    test('the run ends with the reason and sends nothing', () async {
      final claude = FakeLlmProvider(const []);
      final phala = FakeLlmProvider([ScriptedTurn.text('nie')]);
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(
          profiles: [
            for (final p in conceptProfiles())
              RoutingProfile(
                id: p.id,
                name: p.name,
                privacy: p.privacy,
                defaultModel: p.defaultModel,
                enabled: p.id != 'claude',
                provider: p.id == 'phala' ? phala : p.provider,
                aliases: p.aliases,
              ),
          ],
        ),
      );
      final events = await h.run('nochmal mit Claude API', language: 'en');
      final end = terminal(events) as AgentFailed;
      expect(end.message, contains('Claude API is not available'));
      expect(end.message, contains('switched off'));
      expect(events.whereType<Routed>(), isEmpty);
      expect(phala.requests, isEmpty);
      expect(claude.requests, isEmpty);
    });
  });
}
