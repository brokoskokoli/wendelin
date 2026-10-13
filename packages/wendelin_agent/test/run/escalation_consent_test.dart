// Escalation: privacy consent and escalation reasons.

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('escalation', () {
    test('privacy boundary: tee → standard needs consent, declined', () async {
      final (tee, pt) = scripted('phala', [
        ScriptedTurn.error(const ProviderTimeoutException('langsam')),
        ScriptedTurn.error(const ProviderTimeoutException('langsam')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        isPrivate: (i) => i.text.contains('privat'),
      );
      final events = await h.run(
        'privat: Wie ist mein Kontostand?',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(false);
        },
      );
      expect(pt.requests, hasLength(2));
      expect(ps.requests, isEmpty);
      final question = events
          .whereType<EscalationConfirmationRequired>()
          .single;
      expect(
        (question.fromProfile, question.toProfile, question.reason),
        ('phala', 'claude', EscalationReason.providerError),
      );
      expect(events.whereType<Escalated>(), isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.provider);
      expect((events.first as Routed).reason, 'Privat');
    });

    test('privacy boundary: consent given → standard answers', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.error(const ProviderTimeoutException('langsam')),
        ScriptedTurn.error(const ProviderTimeoutException('langsam')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        isPrivate: (i) => i.text.contains('privat'),
      );
      final events = await h.run(
        'privat: x',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(true);
        },
      );
      expect(ps.requests, hasLength(1));
      expect(events.whereType<Escalated>().single.toProfile, 'claude');
      expect(terminal(events), isA<AgentDone>());
    });

    test('privacy boundary: no question for a non-private request', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.error(const ProviderTimeoutException('langsam')),
        ScriptedTurn.error(const ProviderTimeoutException('langsam')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('Claude hier.')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        isPrivate: (i) => i.text.contains('privat'),
      );
      final events = await h.run('Wetter?');
      expect(events.whereType<EscalationConfirmationRequired>(), isEmpty);
      expect(ps.requests, hasLength(1));
    });

    test('declined escalation consent is not asked again', () async {
      final tool = FakeTool(name: 'web__search');
      final (tee, pt) = scripted('phala', [
        ScriptedTurn.toolCalls([call('c1', 'unbekannt__x')]),
        ScriptedTurn.toolCalls([call('c2', 'unbekannt__y')]),
        ScriptedTurn.toolCalls([call('c3', 'unbekannt__z')]),
        ScriptedTurn.text('Phala bleibt.'),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(
        primary: tee,
        chain: [std],
        tools: [tool],
        isPrivate: (_) => true,
      );
      final events = await h.run(
        'x',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) e.respond(false);
        },
      );
      expect(events.whereType<EscalationConfirmationRequired>(), hasLength(1));
      expect(ps.requests, isEmpty);
      expect(pt.requests, hasLength(4));
      expect((terminal(events) as AgentDone).finalText, 'Phala bleibt.');
    });

    test('cancel while the escalation question is pending', () async {
      final (tee, _) = scripted('phala', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: tee, chain: [std], isPrivate: (_) => true);
      final events = await h.run(
        'x',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) h.runner.cancel();
        },
      );
      expect(ps.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
      expect(
        events.whereType<EscalationConfirmationRequired>().single.answered,
        isTrue,
      );
    });

    test('an abort while the question is open wins over a „Ja“', () async {
      // M17: answered „Ja“, then cancelled before the run resumed – no
      // hand-over, the run ends as cancelled.
      final (tee, _) = scripted('phala', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ], privacy: PrivacyLevel.tee);
      final (std, ps) = scripted('claude', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: tee, chain: [std], isPrivate: (_) => true);
      final events = await h.run(
        'x',
        onEvent: (e) {
          if (e is EscalationConfirmationRequired) {
            e.respond(true);
            h.runner.cancel();
          }
        },
      );
      expect(events.whereType<Escalated>(), isEmpty);
      expect(ps.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
    });

    test('twice invalid tool calls → escalation', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__erstellen', '{}')]),
        ScriptedTurn.toolCalls([call('c2', 'cal__create', '{"title":')]),
        ScriptedTurn.text('nie'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('B macht das.')]);
      final h = Harness(primary: a, chain: [b], tools: [tool]);
      final events = await h.run('x');

      expect(tool.callCount, 0);
      expect(
        events.whereType<Escalated>().single.reason,
        EscalationReason.invalidToolCalls,
      );
      // B sees both error results.
      final results = pb.requests.single.messages
          .where((m) => m.role == Role.tool)
          .expand((m) => m.content.cast<ToolResultBlock>());
      expect(results.map((r) => r.isError), [true, true]);
      expect((terminal(events) as AgentDone).finalText, 'B macht das.');
    });

    test('one invalid tool call does not escalate', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__erstellen')]),
        ScriptedTurn.toolCalls([call('c2', 'cal__create')]),
        ScriptedTurn.text('A fertig.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: a, chain: [b], tools: [tool]);
      final events = await h.run('x');
      expect(pb.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'A fertig.');
    });

    test('more than N rounds without result → escalation', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        for (var i = 1; i <= 3; i++)
          ScriptedTurn.toolCalls([call('a$i', 'web__search', '{"n":$i}')]),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('B weiß es.')]);
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [tool],
        config: const AgentConfig(escalateAfterRoundsWithoutResult: 2),
      );
      final events = await h.run('x');
      expect(tool.callCount, 2);
      expect(
        events.whereType<Escalated>().single.reason,
        EscalationReason.noProgress,
      );
      // The unexecuted 3rd request of A is not in B's history.
      expect(pb.requests.single.messages.last.role, Role.tool);
      expect(
        pb.requests.single.messages.expand((m) => m.toolCalls).map((c) => c.id),
        ['a1', 'a2'],
      );
      expect(terminal(events), isA<AgentDone>());
    });

    test('model gives up → escalation; answer not recorded', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.text('Das kann ich leider nicht.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('Doch, so geht es.')]);
      final h = Harness(primary: a, chain: [b]);
      final events = await h.run('x');
      expect(
        events.whereType<Escalated>().single.reason,
        EscalationReason.modelGaveUp,
      );
      expect(pb.requests.single.messages, [Message.user('x')]);
      expect((terminal(events) as AgentDone).finalText, 'Doch, so geht es.');
      expect(h.conversation.messages, [
        Message.user('x'),
        Message.assistantText('Doch, so geht es.'),
      ]);
    });

    test('model gives up without chain → answer stands', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('Das kann ich nicht.')]);
      final events = await Harness(primary: a).run('x');
      expect((terminal(events) as AgentDone).finalText, 'Das kann ich nicht.');
    });

    test('user requested escalation starts with the next link', () async {
      final (a, pa) = scripted('a', [ScriptedTurn.text('nie')]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('B hier.')]);
      final h = Harness(primary: a, chain: [b]);
      final events = await h.run('nochmal mit Claude', requestEscalation: true);
      expect(events.first, isA<Routed>());
      expect(events[1], isA<Escalated>());
      expect((events[1] as Escalated).reason, EscalationReason.userRequested);
      expect(pa.requests, isEmpty);
      expect(pb.requests, hasLength(1));
      expect(pb.requests.single.systemPrompt, isNot(contains('Übergabe')));
    });

    test('non-retryable error does not escalate', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.error(const InvalidRequestException('kaputt')),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final events = await Harness(primary: a, chain: [b]).run('x');
      expect(pb.requests, isEmpty);
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.provider);
    });
  });
}
