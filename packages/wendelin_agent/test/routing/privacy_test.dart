import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';
import 'fixtures.dart';

/// Concept profiles with the given scripted adapters.
List<RoutingProfile> withProviders(
  Map<String, LlmProvider> providers, {
  Set<String> disabled = const {},
}) => [
  for (final p in conceptProfiles(disabled: disabled))
    RoutingProfile(
      id: p.id,
      name: p.name,
      privacy: p.privacy,
      defaultModel: p.defaultModel,
      enabled: p.enabled,
      provider: providers[p.id] ?? p.provider,
      aliases: p.aliases,
    ),
];

/// All text the provider ever received.
String sentText(FakeLlmProvider p) => [
  for (final r in p.requests)
    for (final m in r.messages)
      for (final b in m.content)
        switch (b) {
          TextBlock(:final text) => text,
          ToolCallBlock(:final argumentsJson) => argumentsJson,
          ToolResultBlock(:final content) =>
            content.whereType<TextBlock>().map((t) => t.text).join(),
          _ => '',
        },
].join('\n');

void main() {
  const secret = 'meine Diagnose ist Diabetes';

  group('„nochmal mit Claude“ after a private turn (blocker 1)', () {
    late FakeLlmProvider phala;
    late FakeLlmProvider claude;
    late Harness h;

    setUp(() {
      phala = FakeLlmProvider([
        ScriptedTurn.text('Befund notiert.'),
        ScriptedTurn.text('Phala bleibt dran.'),
      ]);
      claude = FakeLlmProvider([ScriptedTurn.text('Claude hier.')]);
      final (primary, _) = scripted('x', const []);
      h = Harness(
        primary: primary,
        resolver: conceptResolver(
          profiles: withProviders({'phala': phala, 'claude': claude}),
        ),
      );
    });

    test('the private turn is stored with its floor', () async {
      final events = await h.run('privat: $secret');
      expect((events.first as Routed).reason, 'Privat');
      expect(h.conversation.messages, hasLength(2));
      expect(
        h.conversation.messages.map((m) => m.privacyFloor),
        everyElement(PrivacyLevel.tee),
      );
    });

    test('declined: nothing reaches Claude, the retry stays private', () async {
      await h.run('privat: $secret');
      final asked = <EscalationConfirmationRequired>[];
      final events = await h.run(
        'nochmal mit Claude',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            asked.add(e);
            e.respond(false);
          }
        },
      );
      expect(asked.single.toProfile, 'claude');
      expect(claude.requests, isEmpty);
      expect(events.whereType<Escalated>(), isEmpty);
      expect(terminal(events), isA<AgentDone>());
      expect(sentText(phala), contains(secret));
      // The retry turn inherits the floor.
      expect(h.conversation.messages[2].privacyFloor, PrivacyLevel.tee);
    });

    test('approved: Claude gets the private turn', () async {
      await h.run('privat: $secret');
      final events = await h.run(
        'nochmal mit Claude',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(true);
        },
      );
      expect(events.whereType<Escalated>().single.toProfile, 'claude');
      expect(sentText(claude), contains(secret));
    });

    test('retry without a name keeps the floor too', () async {
      final (primary, _) = scripted('x', const []);
      final h2 = Harness(
        primary: primary,
        resolver: conceptResolver(
          rules: conceptRules(
            chains: {
              'phala': [claudeSonnet],
            },
          ),
          profiles: withProviders({'phala': phala, 'claude': claude}),
        ),
      );
      await h2.run('privat: $secret');
      final asked = <EscalationConfirmationRequired>[];
      await h2.run(
        'das war falsch',
        requestEscalation: true,
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            asked.add(e);
            e.respond(false);
          }
        },
      );
      expect(asked.single.toProfile, 'claude');
      expect(claude.requests, isEmpty);
    });
  });

  group('earlier private turns are hidden from weaker targets (2)', () {
    test('a normal follow-up to Claude gets placeholders only', () async {
      final phala = FakeLlmProvider([ScriptedTurn.text('Befund notiert.')]);
      final claude = FakeLlmProvider([ScriptedTurn.text('Sonnig.')]);
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(
          profiles: withProviders({'phala': phala, 'claude': claude}),
        ),
      );
      await h.run('privat: $secret');
      final events = await h.run('Claude, wie wird das Wetter?');
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      final sent = claude.requests.single.messages;
      expect(sentText(claude), isNot(contains('Diabetes')));
      expect(sentText(claude), isNot(contains('Befund')));
      expect(sent.map((m) => (m.role, m.text)).toList(), [
        (Role.user, AgentRunnerTexts.privateHidden),
        (Role.assistant, AgentRunnerTexts.privateHidden),
        (Role.user, 'wie wird das Wetter?'),
      ]);
      // The new turn is not private and stored as is.
      expect(h.conversation.messages[2].privacyFloor, isNull);
    });

    final history =
        [
            Message.user('privat: $secret'),
            Message.assistant([call('c1', 'notes__read')]),
            Message.toolResults([
              ToolResultBlock(
                callId: 'c1',
                content: const [TextBlock('Laborwert 140')],
              ),
            ]),
            Message.assistantText('Dein Wert ist 140.'),
          ].map((m) => m.withPrivacyFloor(PrivacyLevel.tee)).toList()
          ..addAll([Message.user('Hallo'), Message.assistantText('Hi')]);

    test('tool calls and results of the private turn disappear', () async {
      final (primary, provider) = scripted('claude', [ScriptedTurn.text('ok')]);
      final h = Harness(primary: primary, history: history);
      await h.run('Wetter?');
      final sent = provider.requests.single.messages;
      expect(sentText(provider), isNot(contains('140')));
      expect(sentText(provider), isNot(contains('Diabetes')));
      expect(sent.expand((m) => m.content).whereType<ToolCallBlock>(), isEmpty);
      expect(
        sent.expand((m) => m.content).whereType<ToolResultBlock>(),
        isEmpty,
      );
      expect(sent.map((m) => m.text).toList(), [
        AgentRunnerTexts.privateHidden,
        AgentRunnerTexts.privateHidden,
        'Hallo',
        'Hi',
        'Wetter?',
      ]);
    });

    test('targets at the floor see everything', () async {
      final (primary, provider) = scripted('phala', [
        ScriptedTurn.text('ok'),
      ], privacy: PrivacyLevel.tee);
      final h = Harness(primary: primary, history: history);
      await h.run('Wetter?');
      expect(sentText(provider), contains('140'));
      expect(sentText(provider), contains(secret));
    });

    test('a run that saw them is tainted: escalation below asks', () async {
      final (primary, phala) = scripted('phala', [
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
      ], privacy: PrivacyLevel.tee);
      final (claudeTarget, claude) = scripted('claude', [
        ScriptedTurn.text('Hier.'),
      ]);
      final h = Harness(
        primary: primary,
        chain: [claudeTarget],
        history: history,
      );
      final asked = <EscalationConfirmationRequired>[];
      await h.run(
        'Wetter?',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            asked.add(e);
            e.respond(false);
          }
        },
      );
      expect(asked.single.toProfile, 'claude');
      expect(sentText(phala), contains(secret));
      expect(claude.requests, isEmpty);
      expect(
        h.conversation.messages.skip(history.length).map((m) => m.privacyFloor),
        everyElement(PrivacyLevel.tee),
      );
    });

    test('a hidden turn without answer gives only the user placeholder', () {
      final hist = [
        Message.user('privat: x').withPrivacyFloor(PrivacyLevel.local),
        Message.user('Hallo'),
      ];
      final (primary, provider) = scripted('phala', [
        ScriptedTurn.text('ok'),
      ], privacy: PrivacyLevel.tee);
      final h = Harness(primary: primary, history: hist);
      return h.run('Wetter?').then((_) {
        expect(provider.requests.single.messages.map((m) => m.text), [
          AgentRunnerTexts.privateHidden,
          'Hallo',
          'Wetter?',
        ]);
      });
    });
  });

  group('privacy does not fail open (3) and ignores rule order (6)', () {
    RuleSet weakDefault({List<RouteTarget> chain = const []}) => RuleSet(
      rules: [
        RoutingRule(
          id: 'private',
          name: 'Privat',
          condition: PrivacyCondition(),
          target: phalaSmall,
        ),
      ],
      defaultTarget: claudeSonnet,
      chains: {'claude': chain},
    );

    test('private rule target disabled: floor tee, compliant fallback', () {
      final resolver = conceptResolver(
        rules: weakDefault(chain: [claudeOpus, ollama]),
        profiles: conceptProfiles(disabled: {'phala'}),
      );
      final r = resolver.resolve(UserInput(text: 'privat: $secret'));
      expect(r.privacyFloor, PrivacyLevel.tee);
      expect(r.profileId, 'ollama');
      expect(r.belowPrivacyFloor, isFalse);
    });

    test('private rule target without adapter: floor tee as well', () {
      final resolver = conceptResolver(
        profiles: conceptProfiles(unbuildable: {'phala'}),
        rules: conceptRules().copyWith(defaultTarget: ollama),
      );
      final r = resolver.resolve(UserInput(text: 'privat: x'));
      expect(r.privacyFloor, PrivacyLevel.tee);
      expect(r.profileId, 'ollama');
    });

    test('no compliant target: the agent does not send', () async {
      final claude = FakeLlmProvider([ScriptedTurn.text('nein')]);
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(
          rules: weakDefault(),
          profiles: withProviders({'claude': claude}, disabled: {'phala'}),
        ),
      );
      final events = await h.run('privat: $secret');
      expect(claude.requests, isEmpty);
      final failed = terminal(events) as AgentFailed;
      expect(failed.message, AgentRunnerTexts.noPrivateTarget);
      expect(h.conversation.messages.single.privacyFloor, PrivacyLevel.tee);
    });

    test('a private match after the winning rule still sets the floor', () {
      final resolver = conceptResolver();
      final r = resolver.resolve(UserInput(text: 'Claude, privat: $secret'));
      expect(r.privacyFloor, PrivacyLevel.tee);
      expect(r.profileId, 'phala');
      expect(r.reason, 'Privat');
      expect(r.effectiveText, isNull);
      final d = explain(conceptRules(), ctxFor('Claude, privat: x'));
      expect(d.rule!.id, 'strong');
      expect(d.private, isTrue);
      expect(d.privateMatches.single.id, 'private');
    });

    test('a winning private rule keeps its target and floor', () {
      final r = conceptResolver().resolve(UserInput(text: 'privat: x'));
      expect((r.profileId, r.privacyFloor), ('phala', PrivacyLevel.tee));
    });

    test('a strong private target raises the floor', () {
      final rules = conceptRules().copyWith(
        rules: [
          RoutingRule(
            id: 'local',
            name: 'Ganz privat',
            condition: PrivacyCondition(['streng privat']),
            target: ollama,
          ),
          ...conceptRules().rules,
        ],
      );
      final r = conceptResolver(rules: rules)
          .resolve(UserInput(text: 'streng privat: x'));
      expect((r.profileId, r.privacyFloor), ('ollama', PrivacyLevel.local));
    });

    test('disabled private rules do not count', () {
      final rules = conceptRules().copyWith(
        rules: [
          for (final r in conceptRules().rules)
            r.id == 'private' ? r.copyWith(enabled: false) : r,
        ],
      );
      final r = conceptResolver(rules: rules)
          .resolve(UserInput(text: 'Claude, privat: x'));
      expect((r.profileId, r.privacyFloor), ('claude', null));
    });
  });

  group('mutation gaps (7)', () {
    test('not(privacy) matching without the word is not private', () {
      final rules = RuleSet(
        rules: [
          RoutingRule(
            id: 'n',
            name: 'Nicht privat',
            condition: NotCondition(PrivacyCondition()),
            target: claudeOpus,
          ),
        ],
        defaultTarget: phalaSmall,
      );
      final r = conceptResolver(rules: rules).resolve(UserInput(text: 'hallo'));
      expect(r.reason, 'Nicht privat');
      expect(r.privacyFloor, isNull);
      expect(explain(rules, ctxFor('hallo')).private, isFalse);
    });

    test('alias tie: the rule alias wins over the profile name', () {
      final rules = conceptRules().copyWith(
        rules: [
          RoutingRule(
            id: 'm',
            name: 'Mistral über Claude',
            condition: KeywordCondition(['xyz']),
            target: claudeOpus,
            aliases: ['Mistral'],
          ),
        ],
      );
      final r = conceptResolver(rules: rules)
          .resolve(UserInput(text: 'nochmal mit Mistral'));
      expect(r.requestedTarget!.modelId, 'claude-opus');
    });
  });

  test(
    '„nochmal mit <aktuelles Ziel>“ retries there without handover (8)',
    () async {
      final phala = FakeLlmProvider([ScriptedTurn.text('Nochmal.')]);
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(profiles: withProviders({'phala': phala})),
      );
      final events = await h.run('nochmal mit Phala GLM klein');
      expect(events.whereType<Escalated>(), isEmpty);
      expect(phala.requests.single.model, 'glm-small');
      expect(terminal(events), isA<AgentDone>());
    },
  );

  group('taint propagation (re-review 1)', () {
    const geheim = 'Diagnose Diabetes-GEHEIM';

    test('private → summary at Phala → Claude sees nothing of it', () async {
      final phala = FakeLlmProvider([
        ScriptedTurn.text('Notiert.'),
        ScriptedTurn.text('Kurz: $geheim.'),
      ]);
      final claude = FakeLlmProvider([ScriptedTurn.text('Meinung.')]);
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(
          profiles: withProviders({'phala': phala, 'claude': claude}),
        ),
      );
      await h.run('privat: $geheim');
      final summary = await h.run('fasse das kurz zusammen');
      expect((summary.first as Routed).reason, 'Standard');
      expect(sentText(phala), contains(geheim));
      // The summary turn saw the private turn: stored with its floor.
      expect(
        h.conversation.messages.skip(2).map((m) => m.privacyFloor),
        everyElement(PrivacyLevel.tee),
      );
      await h.run('Claude, was meinst du dazu?');
      expect(sentText(claude), isNot(contains('GEHEIM')));
      expect(sentText(claude), isNot(contains('Diabetes')));
      expect(claude.requests.single.messages.map((m) => m.text).toList(), [
        AgentRunnerTexts.privateHidden,
        AgentRunnerTexts.privateHidden,
        AgentRunnerTexts.privateHidden,
        AgentRunnerTexts.privateHidden,
        'was meinst du dazu?',
      ]);
      expect(h.conversation.messages[4].privacyFloor, isNull);
    });

    test('tainted run escalating to Claude asks first', () async {
      final phala = FakeLlmProvider([
        ScriptedTurn.text('Notiert.'),
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
        ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
      ]);
      final claude = FakeLlmProvider([ScriptedTurn.text('Zusammenfassung')]);
      final (primary, _) = scripted('x', const []);
      final h = Harness(
        primary: primary,
        resolver: conceptResolver(
          rules: conceptRules(
            chains: {
              'phala': [claudeSonnet],
            },
          ),
          profiles: withProviders({'phala': phala, 'claude': claude}),
        ),
      );
      await h.run('privat: $geheim');
      final asked = <EscalationConfirmationRequired>[];
      await h.run(
        'fasse das kurz zusammen',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            asked.add(e);
            e.respond(false);
          }
        },
      );
      expect(asked.single.toProfile, 'claude');
      expect(claude.requests, isEmpty);
    });

    test(
      'escalation from Claude to Phala taints the rest of the run',
      () async {
        final phala = FakeLlmProvider([
          ScriptedTurn.text('Notiert.'),
          ScriptedTurn.text('Kurz: $geheim.'),
        ]);
        final claude = FakeLlmProvider([
          ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
          ScriptedTurn.error(const ServerException('kaputt', statusCode: 500)),
          ScriptedTurn.text('Meinung.'),
        ]);
        final (primary, _) = scripted('x', const []);
        final h = Harness(
          primary: primary,
          resolver: conceptResolver(
            rules: conceptRules(
              chains: {
                'claude': [phalaLarge],
              },
            ),
            profiles: withProviders({'phala': phala, 'claude': claude}),
          ),
        );
        await h.run('privat: $geheim');
        final events = await h.run('Claude, fasse das kurz zusammen');
        expect(events.whereType<Escalated>().single.toProfile, 'phala');
        // Claude's failed attempts saw placeholders only.
        expect(sentText(claude), isNot(contains('GEHEIM')));
        final turn2 = h.conversation.messages.skip(2).toList();
        expect(turn2.first.privacyFloor, isNull, reason: 'user text');
        expect(turn2.last.text, contains('GEHEIM'));
        expect(turn2.last.privacyFloor, PrivacyLevel.tee);
        await h.run('Claude, was meinst du dazu?');
        expect(sentText(claude), isNot(contains('GEHEIM')));
      },
    );
  });

  group('memory of private runs (re-review 2)', () {
    final memory = FixedMemoryRetriever([
      const MemoryItem(id: 'm1', text: 'Mag Tee'),
      const MemoryItem(
        id: 'm2',
        text: 'Knie-OP im März',
        privacyFloor: PrivacyLevel.tee,
      ),
    ]);

    test('private entries stay out of the prompt of weaker targets', () async {
      final (primary, claude) = scripted('claude', [ScriptedTurn.text('ok')]);
      final h = Harness(primary: primary, memory: memory);
      await h.run('Wie geht es dem Knie?');
      final prompt = claude.requests.single.systemPrompt!;
      expect(prompt, contains('Mag Tee'));
      expect(prompt, isNot(contains('Knie-OP')));
      expect(
        h.conversation.messages.map((m) => m.privacyFloor),
        everyElement(isNull),
      );
    });

    test('a target of their level sees them and the run is tainted', () async {
      final (primary, phala) = scripted('phala', [
        ScriptedTurn.text('ok'),
      ], privacy: PrivacyLevel.tee);
      final h = Harness(primary: primary, memory: memory);
      await h.run('Wie geht es dem Knie?');
      expect(phala.requests.single.systemPrompt, contains('Knie-OP'));
      expect(
        h.conversation.messages.map((m) => m.privacyFloor),
        everyElement(PrivacyLevel.tee),
      );
    });

    test('tools of a private run get its floor (memory__save)', () async {
      final invoker = ContextInvoker();
      final (primary, _) = scripted('phala', [
        ScriptedTurn.toolCalls([call('c1', 'memory__save')]),
        ScriptedTurn.text('Gemerkt.'),
      ], privacy: PrivacyLevel.tee);
      final h = Harness(
        primary: primary,
        invoker: invoker,
        isPrivate: (i) => i.text.startsWith('privat'),
      );
      await h.run('privat: merk dir die Knie-OP');
      expect(invoker.contexts.single.privacyFloor, PrivacyLevel.tee);
      await h.run('Wetter?');
      expect(invoker.contexts, hasLength(1));
    });
  });

  test('five filler words are too many (3)', () {
    final r = conceptResolver().resolve(
      UserInput(text: 'und bitte kannst du das nochmal mit Claude'),
    );
    expect(r.requestedTarget, isNull);
    final four = conceptResolver().resolve(
      UserInput(text: 'bitte kannst du das nochmal mit Claude'),
    );
    expect(four.requestedTarget, isNotNull);
  });
}
