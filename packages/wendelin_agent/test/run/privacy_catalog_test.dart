// WP14: risk level, tool catalog and redaction per target.

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('WP14: risk level and catalog per target', () {
    test('ConfirmationRequired carries the effective risk', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'cal__create', risk: RiskLevel.write)],
        invoker: RiskInvoker(RiskLevel.external),
      );
      final events = await h.run(
        'x',
        onEvent: (e) {
          if (e is ConfirmationRequired) e.respond(true);
        },
      );
      expect(
        events.whereType<ConfirmationRequired>().single.risk,
        RiskLevel.external,
      );
      final (b, _) = scripted('b', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create')]),
        ScriptedTurn.text('ok'),
      ]);
      final h2 = Harness(
        primary: b,
        tools: [FakeTool(name: 'cal__create', risk: RiskLevel.write)],
        invoker: RiskInvoker(RiskLevel.write),
      );
      final events2 = await h2.run(
        'x',
        onEvent: (e) {
          if (e is ConfirmationRequired) e.respond(false);
        },
      );
      expect(
        events2.whereType<ConfirmationRequired>().single.risk,
        RiskLevel.write,
      );
    });

    test(
      'ConfirmationRequired carries privateDetails (default false)',
      () async {
        for (final priv in [true, false]) {
          final (a, _) = scripted('a', [
            ScriptedTurn.toolCalls([call('c1', 'sms__compose')]),
            ScriptedTurn.text('ok'),
          ]);
          final h = Harness(
            primary: a,
            tools: [FakeTool(name: 'sms__compose', risk: RiskLevel.external)],
            invoker: RiskInvoker(RiskLevel.external, privateDetails: priv),
          );
          final events = await h.run(
            'x',
            onEvent: (e) {
              if (e is ConfirmationRequired) e.respond(true);
            },
          );
          expect(
            events.whereType<ConfirmationRequired>().single.privateDetails,
            priv,
          );
        }
      },
    );

    late FakeTool contacts;
    late FakeTool web;
    ToolCatalog catalogFor(PrivacyLevel level) =>
        FakeToolCatalog([if (level.isAtLeast(PrivacyLevel.tee)) contacts, web]);
    final refused = <String>[];
    Harness harness(
      ProviderTarget primary,
      List<ProviderTarget> chain, {
      List<Message> history = const [],
    }) {
      refused.clear();
      contacts = FakeTool(
        name: 'contacts__find',
        outcome: ToolOutcome.text('Anna: 0171 1234567'),
      );
      web = FakeTool(name: 'web__search');
      return Harness(
        primary: primary,
        chain: chain,
        tools: [web], // ContextBuilder catalog (lowest level)
        invoker: FakeToolInvoker(FakeToolCatalog([contacts, web])),
        catalogFor: catalogFor,
        onToolRefused: (session, call) => refused.add('$session:${call.id}'),
        history: history,
      );
    }

    test(
      'WP135 A: a tool section only goes to targets that get the tool',
      () async {
        // The section tool belongs to the TEE catalog only (K10 per target).
        final house = FakeTool(
          name: 'ha__call',
          section: 'Geräte: Haustür-Licht',
        );
        for (final (level, expected) in [
          (PrivacyLevel.standard, false),
          (PrivacyLevel.tee, true),
        ]) {
          final (p, ps) = scripted('p', [
            ScriptedTurn.text('ok'),
          ], privacy: level);
          final h = Harness(
            primary: p,
            tools: [house],
            catalogFor: (l) =>
                FakeToolCatalog([if (l.isAtLeast(PrivacyLevel.tee)) house]),
          );
          await h.run('Licht an');
          expect(
            ps.requests.single.systemPrompt,
            expected ? contains('Haustür-Licht') : isNot(contains('Haustür')),
            reason: '$level',
          );
        }
      },
    );

    test('(b) protected answers from earlier runs are hidden', () async {
      final history = [
        Message.user('Wie ist Annas Nummer?'),
        Message.assistant([
          const ThinkingBlock('Anna suchen', signature: 's'),
          call('h1', 'contacts__find', '{"q":"Anna"}'),
        ]),
        Message.toolResults([
          ToolResultBlock(
            callId: 'h1',
            content: const [TextBlock('Anna: 0171 1234567')],
          ),
        ]),
        Message.assistant([
          const ThinkingBlock('0171 vorlesen', signature: 't'),
          const TextBlock('Annas Nummer ist '),
          const ProviderBlock(provider: 'fake', rawJson: '{"n":"0171"}'),
          const TextBlock('0171 1234567.'),
        ]),
        Message.user('Danke. Wie wird das Wetter?'),
        Message.assistantText('Sonnig.'),
      ];
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Gern.')]);
      final h = harness(std, const [], history: history);
      await h.run('Und morgen?');
      final sent = ps.requests.single.messages;
      expect(sent.toString(), isNot(contains('0171')));
      expect(sent.toString(), isNot(contains('vorlesen')));
      expect(sent[3].content, [const TextBlock(AgentRunnerTexts.placeholder)]);
      // After the next user message the text is visible again.
      expect(sent[5], Message.assistantText('Sonnig.'));
      expect(sent.last, Message.user('Und morgen?'));
    });

    test(
      '(c) calls of visible tools in a protected section are hidden',
      () async {
        // Run 1 on TEE: contacts, then a web search quoting the number.
        final (tee, _) = scripted('phala', [
          ScriptedTurn.toolCalls([
            call('c1', 'contacts__find', '{"q":"Anna"}'),
          ]),
          ScriptedTurn.toolCalls([
            call('c2', 'web__search', '{"q":"0171 1234567 Anna"}'),
          ]),
          ScriptedTurn.text('Gefunden.'),
        ], privacy: PrivacyLevel.tee);
        final (std, ps) = scripted('claude', [ScriptedTurn.text('ok')]);
        final h = harness(tee, [std]);
        await h.run('Such Annas Nummer im Web');
        expect(web.calls.single['q'], '0171 1234567 Anna');
        final events = await h.run(
          'nochmal mit Claude',
          requestEscalation: true,
        );
        // Earlier protected sections are hidden, so no question is needed.
        expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
        final sent = ps.requests.single.messages;
        expect(sent.toString(), isNot(contains('0171')));
        final webCall = sent.expand((m) => m.toolCalls).last;
        expect(webCall.name, 'web__search');
        expect(webCall.argumentsJson, '{}');
      },
    );

    test('(c) without tools the protected call text is hidden too', () async {
      final history = [
        Message.user('Annas Nummer suchen'),
        Message.assistant([call('h1', 'contacts__find', '{"q":"Anna"}')]),
        Message.toolResults([
          ToolResultBlock(
            callId: 'h1',
            content: const [TextBlock('Anna: 0171 1234567')],
          ),
        ]),
        Message.assistant([call('h2', 'web__search', '{"q":"0171"}')]),
        Message.toolResults([
          ToolResultBlock(callId: 'h2', content: const [TextBlock('0171 …')]),
        ]),
      ];
      final (std, ps) = scripted('claude', [ScriptedTurn.text('ok')]);
      final h = Harness(
        primary: std,
        history: history,
        catalogFor: (_) => FakeToolCatalog(const []),
      );
      await h.run('Danke');
      final sent = ps.requests.single.messages;
      expect(sent.toString(), isNot(contains('0171')));
      expect(sent[3].text, '[Tool-Aufruf: web__search]');
    });

    test(
      '(d) a protected message that would be empty gets a placeholder',
      () async {
        final history = [
          Message.user('Annas Nummer?'),
          Message.assistant([call('h1', 'contacts__find', '{"q":"Anna"}')]),
          Message.toolResults([
            ToolResultBlock(
              callId: 'h1',
              content: const [TextBlock('Anna: 0171 1234567')],
            ),
          ]),
          Message.assistant([
            const ThinkingBlock('0171 merken', signature: 's'),
            const ProviderBlock(provider: 'fake', rawJson: '{"n":"0171"}'),
          ]),
        ];
        final (std, ps) = scripted('claude', [ScriptedTurn.text('ok')]);
        final h = harness(std, const [], history: history);
        await h.run('Weiter');
        final sent = ps.requests.single.messages;
        expect(sent.toString(), isNot(contains('0171')));
        expect(sent[3], Message.assistantText(AgentRunnerTexts.placeholder));
      },
    );

    test('tools get the privacy level of the current target', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.toolCalls([call('c1', 'web__search')]),
        ScriptedTurn.text('ok'),
      ], privacy: PrivacyLevel.tee);
      final invoker = ContextInvoker();
      final h = Harness(
        primary: tee,
        tools: [FakeTool(name: 'web__search')],
        invoker: invoker,
        catalogFor: (_) => FakeToolCatalog([FakeTool(name: 'web__search')]),
      );
      await h.run('x');
      expect(invoker.contexts.single.privacyLevel, PrivacyLevel.tee);
    });

    test('without tools for the target, tool blocks become text', () async {
      final history = [
        Message.user('Timer?'),
        Message.assistant([call('h1', 'alarms__set', '{"m":5}')]),
        Message.toolResults([
          ToolResultBlock(callId: 'h1', content: const [TextBlock('gestellt')]),
        ]),
        Message.assistantText('Timer läuft.'),
      ];
      final (std, ps) = scripted('claude', [ScriptedTurn.text('ok')]);
      final h = Harness(
        primary: std,
        history: history,
        catalogFor: (_) => FakeToolCatalog(const []),
      );
      await h.run('Danke');
      final req = ps.requests.single;
      expect(req.tools, isEmpty);
      final blocks = req.messages.expand((m) => m.content);
      expect(blocks.whereType<ToolCallBlock>(), isEmpty);
      expect(blocks.whereType<ToolResultBlock>(), isEmpty);
      expect(req.messages.map((m) => m.role), isNot(contains(Role.tool)));
      // Hidden for this target: neither arguments nor the result.
      expect(req.messages[1].text, '[Tool-Aufruf: alarms__set]');
      expect(req.messages[2].text, contains('ausgeblendet'));
    });

    test('without tools and without catalogFor tool blocks are text', () async {
      final history = [
        Message.user('Timer?'),
        Message.assistant([call('h1', 'alarms__set', '{"m":5}')]),
        Message.toolResults([
          ToolResultBlock(callId: 'h1', content: const [TextBlock('gestellt')]),
        ]),
      ];
      final (std, ps) = scripted('claude', [ScriptedTurn.text('ok')]);
      await Harness(primary: std, history: history).run('Danke');
      final req = ps.requests.single;
      expect(req.messages[1].text, '[Tool-Aufruf: alarms__set {"m":5}]');
      expect(req.messages[2], Message.user('[Tool-Ergebnis: gestellt]'));
    });

    test('a call to a tool the target may not see is refused', () async {
      final (std, ps) = scripted('claude', [
        ScriptedTurn.toolCalls([
          call('c1', 'contacts__find', '{"q":"Anna"}'),
          call('c2', 'web__search', '{"q":"x"}'),
        ]),
        ScriptedTurn.text('ok'),
      ]);
      final h = harness(std, const []);
      final events = await h.run('x');
      expect(contacts.callCount, 0);
      expect(web.callCount, 1);
      final results = lastResults(ps.requests[1]);
      expect(results.first.isError, isTrue);
      expect(
        (results.first.content.single as TextBlock).text,
        contains('nicht zur Verfügung'),
      );
      expect(results.last.isError, isFalse);
      expect(refused, ['s1:c1']);
      expect((h.invoker as FakeToolInvoker).received.map((c) => c.id), ['c2']);
      expect(events.whereType<ToolCallFinished>().map((e) => e.call.id), [
        'c1',
        'c2',
      ]);
    });
  });
  test(
    'a memory entry above the memory floor taints with its own floor',
    () async {
      // M12: an entry counts with the higher of its own floor and
      // `memoryFloor`, so a `local` entry seen by a local target taints the
      // run with `local`, not with the lower `tee`.
      final (local, pl) = scripted('ollama', [
        ScriptedTurn.text('Tee.'),
      ], privacy: PrivacyLevel.local);
      final h = Harness(
        primary: local,
        memory: FixedMemoryRetriever([
          const MemoryItem(
            id: 'm1',
            text: 'Mag Tee',
            privacyFloor: PrivacyLevel.local,
          ),
        ]),
        memoryFloor: PrivacyLevel.tee,
      );
      await h.run('Was trinke ich gern?');
      expect(pl.requests.single.systemPrompt, contains('Mag Tee'));
      expect(h.conversation.messages.first.privacyFloor, PrivacyLevel.local);
    },
  );
}
