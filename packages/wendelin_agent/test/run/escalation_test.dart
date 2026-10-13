// Escalation: hand-over, counters, repeated calls and call ids.

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('escalation', () {
    test('provider error → second profile answers', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.error(const RateLimitException('zu viel')),
        ScriptedTurn.error(const RateLimitException('zu viel')),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('Hier ist B.')]);
      final h = Harness(primary: a, chain: [b]);
      final events = await h.run('x');

      expect(pa.requests, hasLength(2));
      expect(pb.requests, hasLength(1));
      expect(pb.requests.single.model, 'b-model');
      final esc = events.whereType<Escalated>().single;
      expect(
        (esc.fromProfile, esc.toProfile, esc.reason),
        ('a', 'b', EscalationReason.providerError),
      );
      expect((terminal(events) as AgentDone).finalText, 'Hier ist B.');
      final usage = events.whereType<UsageReported>().single;
      expect(usage.profileId, 'b');
    });

    test('tool from round 1 is not executed again after escalation', () async {
      final tool = FakeTool(
        name: 'cal__create',
        risk: RiskLevel.write,
        outcome: ToolOutcome.text('Termin angelegt'),
      );
      final c1 = call('c1', 'cal__create', '{"title":"Tauchen","h":10}');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([c1]),
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ]);
      final (b, pb) = scripted('b', [
        ScriptedTurn.toolCalls([
          c1, // same call id
          call('b7', 'cal__create', '{"h":10,"title":"Tauchen"}'), // same args
          call('b8', 'cal__create', '{"title":"Kino"}'), // new
        ]),
        ScriptedTurn.text('Beide Termine stehen.'),
      ]);
      final h = Harness(primary: a, chain: [b], tools: [tool]);
      final events = await h.run('Trag Tauchen und Kino ein');

      expect(tool.calls, [
        {'title': 'Tauchen', 'h': 10},
        {'title': 'Kino'},
      ]);
      // B got the history incl. tool results and the system note.
      final first = pb.requests.first;
      expect(first.messages.map((m) => m.role), [
        Role.user,
        Role.assistant,
        Role.tool,
      ]);
      expect(first.systemPrompt, contains('bereits ausgeführt'));
      expect(
        first.systemPrompt,
        contains('- cal__create (erledigt, Call-ID c1)'),
      );
      expect(first.systemPrompt, isNot(contains('Tauchen')));
      final results = lastResults(pb.requests[1]);
      // The repeated id c1 gets an internal id; tool_use and tool_result
      // match.
      expect(results.map((r) => r.callId), ['c1_dup1', 'b7', 'b8']);
      expect(pb.requests[1].messages[3].toolCalls.map((c) => c.id), [
        'c1_dup1',
        'b7',
        'b8',
      ]);
      for (final r in results.take(2)) {
        expect((r.content.first as TextBlock).text, startsWith('Bereits'));
        expect((r.content.last as TextBlock).text, 'Termin angelegt');
      }
      final skipped = events.whereType<ToolCallFinished>().where(
        (e) => e.outcome.summary == 'Bereits ausgeführt',
      );
      expect(skipped.map((e) => e.call.id), ['c1_dup1', 'b7']);
      expect(terminal(events), isA<AgentDone>());
    });

    test('counters start fresh at the new provider', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('a1', 'web__search', '{"n":1}')]),
        ScriptedTurn.toolCalls([call('a2', 'nix__da')]),
        ScriptedTurn.toolCalls([call('a3', 'nix__da', '{"x":1}')]),
      ]);
      final (b, _) = scripted('b', [
        ScriptedTurn.toolCalls([call('b1', 'nix__da', '{"y":1}')]),
        ScriptedTurn.toolCalls([call('b2', 'web__search', '{"n":2}')]),
        ScriptedTurn.text('B fertig.'),
      ]);
      final (c, pc) = scripted('c', [ScriptedTurn.text('nie')]);
      final h = Harness(
        primary: a,
        chain: [b, c],
        tools: [tool],
        config: const AgentConfig(escalateAfterRoundsWithoutResult: 2),
      );
      final events = await h.run('x');
      // a: 2 rounds (1 invalid) → 3rd round = noProgress → b. b has 1 invalid
      // and 2 rounds of its own, so no further escalation.
      expect(events.whereType<Escalated>().map((e) => e.reason), [
        EscalationReason.noProgress,
      ]);
      expect(pc.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'B fertig.');
    });

    test('invalid-call counter starts fresh at the new provider', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('a1', 'nix__da')]),
        ScriptedTurn.toolCalls([call('a2', 'nix__da', '{"x":1}')]),
      ]);
      final (b, _) = scripted('b', [
        ScriptedTurn.toolCalls([call('b1', 'nix__da', '{"y":1}')]),
        ScriptedTurn.text('B fertig.'),
      ]);
      final (c, pc) = scripted('c', [ScriptedTurn.text('nie')]);
      final h = Harness(primary: a, chain: [b, c]);
      final events = await h.run('x');
      expect(pc.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'B fertig.');
    });

    test('each model call gets its own retry', () async {
      final (a, pa) = scripted('a', [
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.toolCalls([call('a1', 'web__search')]),
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.text('A fertig.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('nie')]);
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [FakeTool(name: 'web__search')],
      );
      final events = await h.run('x');
      expect(pa.requests, hasLength(4));
      expect(pb.requests, isEmpty);
      expect((terminal(events) as AgentDone).finalText, 'A fertig.');
    });

    test('same call id with same content is not executed twice', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{"t":1}')]),
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{ "t": 1 }')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.calls, [
        {'t': 1},
      ]);
      final result = lastResults(provider.requests[2]).single;
      expect(result.callId, 'c1_dup1');
      expect((result.content.first as TextBlock).text, startsWith('Bereits'));
    });

    test('replacement ids match the strictest provider pattern', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('call:0', 'web__search', '{"n":1}'),
          call('call:0', 'web__search', '{"n":2}'),
          call('call_0', 'web__search', '{"n":3}'),
          call('', 'web__search', '{"n":4}'),
          call('ok-id_1', 'web__search', '{"n":5}'),
        ]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      final ids = provider.requests[1].messages[1].toolCalls
          .map((c) => c.id)
          .toList();
      expect(ids, [
        'call_0',
        'call_0_dup1',
        'call_0_dup2',
        'call_dup1',
        'ok-id_1',
      ]);
      final anthropic = RegExp(r'^[a-zA-Z0-9_-]+$');
      expect(ids.every(anthropic.hasMatch), isTrue);
      expect(lastResults(provider.requests[1]).map((r) => r.callId), ids);
      expect(tool.callCount, 5);
    });

    test('empty ids never count as a repetition', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.toolCalls([call('', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.callCount, 2);
    });

    test(
      'id collision with other content is executed under a new id',
      () async {
        final create = FakeTool(name: 'cal__create');
        final search = FakeTool(name: 'web__search');
        final (a, provider) = scripted('a', [
          ScriptedTurn.toolCalls([call('call_0', 'cal__create', '{"t":1}')]),
          ScriptedTurn.toolCalls([
            call('call_0', 'cal__create', '{"t":2}'),
            call('call_0', 'web__search', '{"q":"x"}'),
            call('', 'web__search', '{"q":"y"}'),
            call('', 'web__search', '{"q":"z"}'),
          ]),
          ScriptedTurn.text('ok'),
        ]);
        final h = Harness(primary: a, tools: [create, search]);
        final events = await h.run('x');
        expect(create.calls, [
          {'t': 1},
          {'t': 2},
        ]);
        expect(search.callCount, 3);
        final messages = provider.requests[2].messages;
        final ids = messages[3].toolCalls.map((c) => c.id).toList();
        expect(ids, ['call_0_dup1', 'call_0_dup2', 'call_dup1', 'call_dup2']);
        expect(lastResults(provider.requests[2]).map((r) => r.callId), ids);
        expect(
          lastResults(provider.requests[2]).every((r) => !r.isError),
          isTrue,
        );
        expect(events.whereType<ToolCallFinished>().map((e) => e.call.id), [
          'call_0',
          ...ids,
        ]);
      },
    );

    test('the same provider may repeat an identical call', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.toolCalls([call('c2', 'web__search', '{"q":"x"}')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.callCount, 2);
    });

    test('invalid JSON calls are compared verbatim after escalation', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{"t":')]),
        ScriptedTurn.toolCalls([call('c2', 'cal__create', '{"u":')]),
      ]);
      final (b, pb) = scripted('b', [
        ScriptedTurn.toolCalls([
          call('b1', 'cal__create', '{"t":'),
          call('b2', 'cal__create', '{"v":'),
        ]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, chain: [b], tools: [tool]);
      final events = await h.run('x');
      final skipped = events.whereType<ToolCallFinished>().where(
        (e) => e.outcome.summary == 'Bereits ausgeführt',
      );
      expect(skipped.map((e) => e.call.id), ['b1']);
      expect(lastResults(pb.requests[1]).map((r) => r.isError), [true, true]);
    });

    test('a paused answer replaced by an escalation is dropped', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.text('Moment.', stopReason: StopReason.pauseTurn),
        ScriptedTurn.text(' Das kann ich leider nicht.'),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('B kann es.')]);
      final h = Harness(primary: a, chain: [b]);
      final events = await h.run('x');
      expect(pb.requests.single.messages, [Message.user('x')]);
      expect((terminal(events) as AgentDone).finalText, 'B kann es.');
    });

    test('declined call may be proposed again after escalation', () async {
      final sms = FakeTool(name: 'sms__send', risk: RiskLevel.external);
      final c1 = call('c1', 'sms__send', '{"to":"Anna"}');
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([c1]),
        ScriptedTurn.text('Das kann ich leider nicht.'),
      ]);
      final (b, _) = scripted('b', [
        ScriptedTurn.toolCalls([call('b1', 'sms__send', '{"to":"Anna"}')]),
        ScriptedTurn.text('Gesendet.'),
      ]);
      final h = Harness(primary: a, chain: [b], tools: [sms]);
      var answers = [false, true];
      await h.run(
        'x',
        onEvent: (e) {
          if (e is ConfirmationRequired) {
            e.respond(answers.first);
            answers = answers.sublist(1);
          }
        },
      );
      expect(sms.callCount, 1);
    });

    test('signed thinking is not sent to the next provider', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.events([
          const ThinkingComplete(ThinkingBlock('t', signature: 's')),
          ToolCallComplete(call('c1', 'web__search')),
          const Done(StopReason.toolUse),
        ]),
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ]);
      final (b, pb) = scripted('b', [ScriptedTurn.text('B')]);
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [FakeTool(name: 'web__search')],
      );
      await h.run('x');
      final assistant = pb.requests.single.messages[1];
      expect(assistant.content, [call('c1', 'web__search')]);
      // The recorded history keeps the original block.
      expect(h.conversation.messages[1].content.first, isA<ThinkingBlock>());
    });

    test(
      'provider blocks of another family are dropped on escalation',
      () async {
        const own = ProviderBlock(provider: 'fake', rawJson: '{"own":1}');
        const foreign = ProviderBlock(
          provider: 'anthropic',
          rawJson: '{"x":1}',
        );
        final c1 = call('c1', 'web__search');
        final (a, _) = scripted('a', [
          ScriptedTurn.events([
            const ProviderBlockComplete(foreign),
            const ProviderBlockComplete(own),
            ToolCallComplete(c1),
            const Done(StopReason.toolUse),
          ]),
          ScriptedTurn.error(const NetworkException('weg')),
          ScriptedTurn.error(const NetworkException('weg')),
        ]);
        // b is a FakeLlmProvider, i.e. family "fake".
        final (b, pb) = scripted('b', [ScriptedTurn.text('B.')]);
        final h = Harness(
          primary: a,
          chain: [b],
          tools: [FakeTool(name: 'web__search')],
        );
        await h.run('x');
        expect(pb.requests.single.messages[1].content, [own, c1]);
        // Stored history keeps everything.
        expect(h.conversation.messages[1].content, [foreign, own, c1]);
      },
    );
  });
}
