import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'support.dart';

void main() {
  group('scenarios', () {
    test('plain text answer', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Hallo Stefan.')]);
      final h = Harness(primary: a, cost: const FlatCostEstimator());
      final events = await h.run('Hallo');

      expect(events.first, isA<Routed>());
      final routed = events.first as Routed;
      expect(
        (routed.profileId, routed.modelId, routed.reason),
        ('a', 'a-model', 'Standard'),
      );
      expect(streamedText(events), 'Hallo Stefan.');
      final usage = events.whereType<UsageReported>().single;
      expect(usage.usage, ScriptedTurn.defaultUsage);
      expect(usage.profileId, 'a');
      expect(usage.modelId, 'a-model');
      expect(usage.costMicros, 200); // 100 in × 1 + 20 out × 5
      final done = terminal(events) as AgentDone;
      expect(done.finalText, 'Hallo Stefan.');
      expect(done.stopReason, StopReason.endTurn);

      final req = provider.requests.single;
      expect(req.model, 'a-model');
      expect(req.maxTokens, 1024);
      expect(req.systemPrompt, contains('Du bist Wendelin'));
      expect(req.messages, [Message.user('Hallo')]);
      expect(req.metadata, {'sessionId': 's1'});
      expect(h.conversation.messages, [
        Message.user('Hallo'),
        Message.assistantText('Hallo Stefan.'),
      ]);
    });

    test('one tool call', () async {
      final tool = FakeTool(
        name: 'cal__create',
        outcome: ToolOutcome.text('Termin angelegt'),
      );
      final c1 = call('c1', 'cal__create', '{"title":"Tauchen"}');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([c1], text: 'Moment. '),
        ScriptedTurn.text('Erledigt.'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final events = await h.run('Trag Tauchen ein');

      expect(tool.calls, [
        {'title': 'Tauchen'},
      ]);
      expect(events.whereType<ToolCallStarted>().single.call, c1);
      final finished = events.whereType<ToolCallFinished>().single;
      expect(finished.outcome.text, 'Termin angelegt');
      expect(finished.duration, Duration.zero);
      expect(provider.requests, hasLength(2));
      expect(provider.requests[1].messages, [
        Message.user('Trag Tauchen ein'),
        Message.assistant([const TextBlock('Moment. '), c1]),
        Message.toolResults([
          ToolResultBlock(
            callId: 'c1',
            content: const [TextBlock('Termin angelegt')],
          ),
        ]),
      ]);
      expect((terminal(events) as AgentDone).finalText, 'Erledigt.');
      expect(streamedText(events), 'Moment. Erledigt.');
      expect(events.whereType<UsageReported>(), hasLength(2));
      expect(h.conversation.messages, hasLength(4));
    });

    test('two parallel tool calls in one round', () async {
      final cal = FakeTool(name: 'cal__list', outcome: ToolOutcome.text('2'));
      final web = FakeTool(name: 'web__search', outcome: ToolOutcome.text('w'));
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('c1', 'cal__list'),
          call('c2', 'web__search', '{"q":"Wetter"}'),
        ]),
        ScriptedTurn.text('Fertig.'),
      ]);
      final h = Harness(primary: a, tools: [cal, web]);
      final events = await h.run('Was steht an?');

      expect(cal.callCount, 1);
      expect(web.callCount, 1);
      expect(events.whereType<ToolCallFinished>().map((e) => e.call.id), [
        'c1',
        'c2',
      ]);
      final results = lastResults(provider.requests[1]);
      expect(results.map((r) => (r.callId, r.isError)), [
        ('c1', false),
        ('c2', false),
      ]);
      expect(terminal(events), isA<AgentDone>());
    });

    for (final approve in [true, false]) {
      test('confirmation answered ${approve ? 'yes' : 'no'}', () async {
        final sms = FakeTool(
          name: 'sms__send',
          risk: RiskLevel.external,
          confirmation: (_) => 'SMS an Anna senden',
        );
        final (a, provider) = scripted('a', [
          ScriptedTurn.toolCalls([call('c1', 'sms__send', '{"to":"Anna"}')]),
          ScriptedTurn.text(approve ? 'Gesendet.' : 'Okay, nicht gesendet.'),
        ]);
        final h = Harness(primary: a, tools: [sms]);
        final events = await h.run(
          'Schreib Anna',
          onEvent: (e) {
            if (e is ConfirmationRequired) e.respond(approve);
          },
        );

        final question = events.whereType<ConfirmationRequired>().single;
        expect(question.description, 'SMS an Anna senden');
        expect(question.call.id, 'c1');
        expect(question.answered, isTrue);
        expect(sms.callCount, approve ? 1 : 0);
        final result = lastResults(provider.requests[1]).single;
        expect(result.isError, isFalse);
        expect(
          (result.content.single as TextBlock).text,
          approve ? 'ok' : ToolOutcome.declinedText,
        );
        expect(terminal(events), isA<AgentDone>());
      });
    }

    test('failing tool: the model gets isError', () async {
      final broken = FakeTool(name: 'cal__create', throws: StateError('weg'));
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create')]),
        ScriptedTurn.text('Das hat nicht geklappt.'),
      ]);
      final h = Harness(primary: a, tools: [broken]);
      final events = await h.run('Trag was ein');

      final result = lastResults(provider.requests[1]).single;
      expect(result.isError, isTrue);
      expect((result.content.single as TextBlock).text, contains('weg'));
      expect(
        events.whereType<ToolCallFinished>().single.outcome.isError,
        isTrue,
      );
      expect(terminal(events), isA<AgentDone>());
    });

    test('the 9th tool round is prevented', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, provider) = scripted('a', [
        for (var i = 1; i <= 9; i++)
          ScriptedTurn.toolCalls([call('c$i', 'web__search', '{"n":$i}')]),
        ScriptedTurn.text('nie erreicht'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final events = await h.run('Such ewig');

      expect(tool.callCount, 8);
      expect(provider.requests, hasLength(9));
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.toolRoundLimit);
      expect(failed.message, contains('8 Tool-Runden'));
      expect(events.whereType<ToolCallStarted>(), hasLength(8));
      // The refused call still has a result in the history.
      final last = h.conversation.messages.last;
      expect(last.role, Role.tool);
      final refused = last.content.single as ToolResultBlock;
      expect(refused.callId, 'c9');
      expect(refused.isError, isTrue);
    });

    test('maxToolRounds is configurable', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, _) = scripted('a', [
        for (var i = 1; i <= 3; i++)
          ScriptedTurn.toolCalls([call('c$i', 'web__search', '{"n":$i}')]),
      ]);
      final h = Harness(
        primary: a,
        tools: [tool],
        config: const AgentConfig(maxToolRounds: 2),
      );
      final events = await h.run('x');
      expect(tool.callCount, 2);
      expect(
        (terminal(events) as AgentFailed).error,
        AgentErrorKind.toolRoundLimit,
      );
    });

    test('time limit via timer while the model hangs', () {
      fakeAsync((async) {
        final (a, provider) = scripted('a', [
          ScriptedTurn.hang(partialText: 'Ich denke'),
        ]);
        final h = Harness(primary: a);
        final events = <AgentEvent>[];
        h.runner.run(UserInput(text: 'x')).listen(events.add);
        async.elapse(const Duration(seconds: 59));
        expect(events.whereType<AgentFailed>(), isEmpty);
        expect(streamedText(events), 'Ich denke');
        async.elapse(const Duration(seconds: 2));
        final failed = events.last as AgentFailed;
        expect(failed.error, AgentErrorKind.timeout);
        expect(failed.message, contains('60 Sekunden'));
        expect(provider.requests, hasLength(1));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('time limit via clock between steps', () async {
      late Harness h;
      final slow = FakeTool(
        name: 'web__search',
        handler: (args, ctx) {
          h.clock.advance(const Duration(seconds: 61));
          return ToolOutcome.text('spät');
        },
      );
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search')]),
        ScriptedTurn.text('nie erreicht'),
      ]);
      h = Harness(primary: a, tools: [slow]);
      final events = await h.run('x');
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.timeout);
      expect(provider.requests, hasLength(1));
      // The executed tool's result is still recorded.
      expect(h.conversation.messages.last.role, Role.tool);
    });

    test('cancel in the middle of the stream', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.hang(partialText: 'Ich fange an und'),
      ]);
      final h = Harness(primary: a);
      final events = await h.run(
        'x',
        onEvent: (e) {
          if (e is AgentTextDelta) h.runner.cancel();
        },
      );
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.cancelled);
      expect(failed.message, 'Abgebrochen.');
      expect(events.whereType<AgentDone>(), isEmpty);
      expect(provider.requests, hasLength(1));
      // Partial assistant text is not recorded.
      expect(h.conversation.messages, [Message.user('x')]);
    });

    test('cancel while a confirmation is pending', () async {
      final sms = FakeTool(name: 'sms__send', risk: RiskLevel.external);
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'sms__send', '{}')]),
        ScriptedTurn.text('nie erreicht'),
      ]);
      final h = Harness(primary: a, tools: [sms]);
      final events = await h.run(
        'Schreib Anna',
        onEvent: (e) {
          if (e is ConfirmationRequired) h.runner.cancel();
        },
      );
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.cancelled);
      expect(sms.callCount, 0);
      expect(provider.requests, hasLength(1));
      final question = events.whereType<ConfirmationRequired>().single;
      expect(question.answered, isFalse);
      final finished = events.whereType<ToolCallFinished>().single;
      expect(finished.outcome.isError, isTrue);
      // Every tool_use has a tool_result in the history.
      final last = h.conversation.messages.last;
      expect(last.role, Role.tool);
      expect((last.content.single as ToolResultBlock).callId, 'c1');
    });

    test('cancel without an active run is a no-op', () {
      final (a, _) = scripted('a', const []);
      Harness(primary: a).runner.cancel();
    });

    test('cancelling the subscription aborts the model call', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.hang(partialText: 'a'),
      ]);
      final h = Harness(primary: a);
      final first = Completer<void>();
      final sub = h.runner.run(UserInput(text: 'x')).listen((e) {
        if (e is AgentTextDelta) first.complete();
      });
      await first.future;
      await sub.cancel();
      await pumpEventQueue();
      expect(provider.requests, hasLength(1));
      // A new run is possible afterwards.
      provider.enqueue(ScriptedTurn.text('Wieder da.'));
      final events = await h.run('y');
      expect((terminal(events) as AgentDone).finalText, 'Wieder da.');
    });

    test('a second concurrent run fails', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('eins')]);
      final h = Harness(primary: a);
      final first = h.runner.run(UserInput(text: '1')).toList();
      final second = await h.runner.run(UserInput(text: '2')).toList();
      expect((second.single as AgentFailed).error, AgentErrorKind.internal);
      expect(terminal(await first), isA<AgentDone>());
    });
  });

  group('core contract', () {
    test('thinking blocks are kept unchanged and in order', () async {
      const t1 = ThinkingBlock('erst denken', signature: 'sig-1');
      const t2 = ThinkingBlock.redacted('opaque');
      final c1 = call('c1', 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.events([
          const ThinkingDelta('erst denken'),
          const ThinkingComplete(t1),
          const TextDelta('Ich '),
          const TextDelta('suche.'),
          const ThinkingComplete(t2),
          const ToolCallDelta(index: 0, id: 'c1', name: 'web__search'),
          ToolCallComplete(c1),
          const UsageEvent(Usage(inputTokens: 5)),
          const UsageEvent(Usage(outputTokens: 7)),
          const Done(StopReason.toolUse),
        ]),
        ScriptedTurn.text('Fertig.'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
      );
      final events = await h.run('x');

      expect(provider.requests[1].messages[1].content, [
        t1,
        const TextBlock('Ich suche.'),
        t2,
        c1,
      ]);
      // Usage events are increments and are summed per call.
      expect(
        events.whereType<UsageReported>().first.usage,
        const Usage(inputTokens: 5, outputTokens: 7),
      );
    });

    test('incomplete tool call of a failed stream is never executed', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, _) = scripted('a', [
        ScriptedTurn.errorDuringToolCall(
          call('c1', 'cal__create', '{"title":"Tauchen"}'),
          const AuthException('Schlüssel ungültig'),
        ),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final events = await h.run('x');
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.provider);
      expect(failed.cause, const AuthException('Schlüssel ungültig'));
      expect(failed.message, contains('Schlüssel ungültig'));
      expect(tool.callCount, 0);
      expect(events.whereType<ToolCallStarted>(), isEmpty);
    });

    test('retryable error: one retry at the same provider', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, provider) = scripted('a', [
        ScriptedTurn.errorDuringToolCall(
          call('c1', 'cal__create', '{"a":1}'),
          const NetworkException('weg'),
        ),
        ScriptedTurn.text('Jetzt klappt es.'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final events = await h.run('x');
      expect(provider.requests, hasLength(2));
      expect(provider.requests[1].messages, [Message.user('x')]);
      expect(tool.callCount, 0);
      expect((terminal(events) as AgentDone).finalText, 'Jetzt klappt es.');
      expect(events.whereType<Escalated>(), isEmpty);
    });

    test('retryable error twice without chain fails', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.error(
          const ServerException('überlastet', statusCode: 529),
        ),
        ScriptedTurn.error(
          const ServerException('überlastet', statusCode: 529),
        ),
      ]);
      final events = await Harness(primary: a).run('x');
      expect(provider.requests, hasLength(2));
      expect((terminal(events) as AgentFailed).error, AgentErrorKind.provider);
    });

    test('pauseTurn continues the turn without counting a round', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.text('Teil eins.', stopReason: StopReason.pauseTurn),
        ScriptedTurn.text(' Teil zwei.'),
      ]);
      final h = Harness(
        primary: a,
        config: const AgentConfig(maxToolRounds: 1),
      );
      final events = await h.run('x');
      expect(provider.requests, hasLength(2));
      expect(provider.requests[1].messages, [
        Message.user('x'),
        Message.assistantText('Teil eins.'),
      ]);
      final done = terminal(events) as AgentDone;
      expect(done.finalText, 'Teil eins. Teil zwei.');
      expect(done.stopReason, StopReason.endTurn);
    });

    test('stream without terminal event fails as malformed', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.events([const TextDelta('halb')]),
      ]);
      final events = await Harness(primary: a).run('x');
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.provider);
      expect(failed.cause, isA<MalformedResponseException>());
    });

    test('empty text deltas are ignored', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.events([
          const TextDelta(''),
          const TextDelta('Hi'),
          const Done(StopReason.endTurn),
        ]),
      ]);
      final events = await Harness(primary: a).run('x');
      expect(events.whereType<AgentTextDelta>().single.text, 'Hi');
      expect(events.whereType<UsageReported>(), isEmpty);
    });
  });

  group('budgets', () {
    test('token budget stops further tool rounds', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search', '{"n":1}')]),
        ScriptedTurn.toolCalls([call('c2', 'web__search', '{"n":2}')]),
        ScriptedTurn.text('nie'),
      ]);
      final h = Harness(
        primary: a,
        tools: [tool],
        config: const AgentConfig(maxTokensPerRequest: 200),
      );
      final events = await h.run('x');
      expect(tool.callCount, 1);
      expect(provider.requests, hasLength(2));
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.tokenBudget);
      final refused = h.conversation.messages.last.content.single;
      expect((refused as ToolResultBlock).callId, 'c2');
    });

    test('token budget is checked before continuing a paused turn', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.text(
          'Teil eins.',
          stopReason: StopReason.pauseTurn,
          usage: const Usage(inputTokens: 90),
        ),
        ScriptedTurn.text('nie'),
      ]);
      final h = Harness(
        primary: a,
        config: const AgentConfig(maxTokensPerRequest: 90),
      );
      final events = await h.run('x');
      expect(
        (terminal(events) as AgentFailed).error,
        AgentErrorKind.tokenBudget,
      );
      expect(provider.requests, hasLength(1));
    });

    test('token budget refuses a tool round at the limit', () async {
      final tool = FakeTool(name: 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('c1', 'web__search'),
        ], usage: const Usage(inputTokens: 90)),
        ScriptedTurn.text('nie'),
      ]);
      final h = Harness(
        primary: a,
        tools: [tool],
        config: const AgentConfig(maxTokensPerRequest: 90),
      );
      // 90 ≥ 90 after the first call: the round is refused.
      final events = await h.run('x');
      expect(
        (terminal(events) as AgentFailed).error,
        AgentErrorKind.tokenBudget,
      );
      expect(provider.requests, hasLength(1));
      expect(tool.callCount, 0);
    });

    test('budget guard blocks before any model call', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('nie')]);
      final guard = FixedBudgetGuard(BudgetStatus.block);
      final h = Harness(primary: a, budget: guard);
      final events = await h.run('x');
      final failed = terminal(events) as AgentFailed;
      expect(failed.error, AgentErrorKind.budgetBlocked);
      expect(provider.requests, isEmpty);
      expect(guard.checked, ['a']);
    });

    test('budget guard warning does not stop the call', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('ok')]);
      final h = Harness(
        primary: a,
        budget: FixedBudgetGuard(BudgetStatus.warn),
      );
      expect(terminal(await h.run('x')), isA<AgentDone>());
    });
  });

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
        contains('cal__create {"title":"Tauchen","h":10} (erledigt)'),
      );
      final results = lastResults(pb.requests[1]);
      expect(results.map((r) => r.callId), ['c1', 'b7', 'b8']);
      for (final r in results.take(2)) {
        expect((r.content.first as TextBlock).text, startsWith('Bereits'));
        expect((r.content.last as TextBlock).text, 'Termin angelegt');
      }
      final skipped = events.whereType<ToolCallFinished>().where(
        (e) => e.outcome.summary == 'Bereits ausgeführt',
      );
      expect(skipped.map((e) => e.call.id), ['c1', 'b7']);
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

    test('the same call id is never executed twice', () async {
      final tool = FakeTool(name: 'cal__create');
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{"t":1}')]),
        ScriptedTurn.toolCalls([call('c1', 'cal__create', '{"t":2}')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.calls, [
        {'t': 1},
      ]);
      final result = lastResults(provider.requests[2]).single;
      expect((result.content.first as TextBlock).text, startsWith('Bereits'));
    });

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

  group('text reset, thinking, budget warning', () {
    /// Event kinds as short labels, for order checks.
    List<String> kinds(List<AgentEvent> events) => [
      for (final e in events)
        switch (e) {
          AgentTextDelta(:final text) => 'T:$text',
          AgentTextReset() => 'RESET',
          Escalated() => 'ESC',
          _ => null,
        },
    ].nonNulls.toList();

    test('retry after streamed text resets it', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.error(
          const NetworkException('weg'),
          partialText: 'Hal',
          chunkSize: 10,
        ),
        ScriptedTurn.text('Hallo.', chunkSize: 10),
      ]);
      final events = await Harness(primary: a).run('x');
      expect(kinds(events), ['T:Hal', 'RESET', 'T:Hallo.']);
      expect(
        events.whereType<AgentTextReset>().single.reason,
        'Neuer Versuch nach Fehler',
      );
    });

    test('retry without streamed text sends no reset', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls(
          [call('c1', 'web__search')],
          text: 'Moment.',
          chunkSize: 10,
        ),
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.text('Fertig.', chunkSize: 10),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
      );
      final events = await h.run('x');
      expect(kinds(events), ['T:Moment.', 'T:Fertig.']);
    });

    test('escalation after provider error resets partial text', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.error(
          const NetworkException('weg'),
          partialText: 'A1',
          chunkSize: 10,
        ),
        ScriptedTurn.error(
          const NetworkException('weg'),
          partialText: 'A2',
          chunkSize: 10,
        ),
      ]);
      final (b, _) = scripted('b', [ScriptedTurn.text('B.', chunkSize: 10)]);
      final events = await Harness(primary: a, chain: [b]).run('x');
      expect(kinds(events), ['T:A1', 'RESET', 'T:A2', 'ESC', 'RESET', 'T:B.']);
    });

    test('escalation after "kann ich nicht" resets the answer', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.text('Das kann ich leider nicht.', chunkSize: 100),
      ]);
      final (b, _) = scripted('b', [ScriptedTurn.text('B.', chunkSize: 10)]);
      final events = await Harness(primary: a, chain: [b]).run('x');
      expect(kinds(events), [
        'T:Das kann ich leider nicht.',
        'ESC',
        'RESET',
        'T:B.',
      ]);
    });

    test('escalation after noProgress resets the dropped text', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls(
          [call('a1', 'web__search')],
          text: 'Eins.',
          chunkSize: 10,
        ),
        ScriptedTurn.toolCalls(
          [call('a2', 'web__search', '{"n":2}')],
          text: 'Zwei.',
          chunkSize: 10,
        ),
      ]);
      final (b, _) = scripted('b', [ScriptedTurn.text('B.', chunkSize: 10)]);
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [FakeTool(name: 'web__search')],
        config: const AgentConfig(escalateAfterRoundsWithoutResult: 1),
      );
      final events = await h.run('x');
      expect(kinds(events), ['T:Eins.', 'T:Zwei.', 'ESC', 'RESET', 'T:B.']);
    });

    test('thinking deltas are passed on', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.events([
          const ThinkingDelta('Hm'),
          const ThinkingDelta(''),
          const ThinkingDelta(', ja'),
          const ThinkingComplete(ThinkingBlock('Hm, ja', signature: 's')),
          const TextDelta('Ja.'),
          const Done(StopReason.endTurn),
        ]),
      ]);
      final events = await Harness(primary: a).run('x');
      expect(events.whereType<AgentThinkingDelta>().map((e) => e.text), [
        'Hm',
        ', ja',
      ]);
      expect(streamedText(events), 'Ja.');
    });

    test('budget warning once per run and profile', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search')]),
        ScriptedTurn.error(const NetworkException('weg')),
        ScriptedTurn.error(const NetworkException('weg')),
      ]);
      final (b, _) = scripted('b', [ScriptedTurn.text('B.')]);
      final guard = FixedBudgetGuard(BudgetStatus.warn, 8000000, 10000000);
      final h = Harness(
        primary: a,
        chain: [b],
        tools: [FakeTool(name: 'web__search')],
        budget: guard,
      );
      final events = await h.run('x');
      final warnings = events.whereType<BudgetWarning>().toList();
      expect(warnings.map((w) => w.profileId), ['a', 'b']);
      expect(warnings.first.spentMicros, 8000000);
      expect(warnings.first.budgetMicros, 10000000);
      expect(guard.checked, ['a', 'a', 'a', 'b']);
      expect(terminal(events), isA<AgentDone>());
      // A new run warns again.
      (b.provider as FakeLlmProvider).enqueue(ScriptedTurn.text('nochmal'));
      final h2 = Harness(primary: b, budget: guard);
      final again = await h2.run('y');
      expect(again.whereType<BudgetWarning>(), hasLength(1));
    });
  });

  group('robustness', () {
    test('invoker without results: every call still gets one', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search')]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
        invoker: SilentInvoker(),
      );
      await h.run('x');
      final result = lastResults(provider.requests[1]).single;
      expect(result.callId, 'c1');
      expect(result.isError, isTrue);
    });

    test('recorder failure ends the run with internal error', () async {
      final (a, _) = scripted('a', [ScriptedTurn.text('ok')]);
      final h = Harness(primary: a, recorder: FailingRecorder());
      final failed = terminal(await h.run('x')) as AgentFailed;
      expect(failed.error, AgentErrorKind.internal);
      expect(failed.cause, isA<StateError>());
    });

    test('provider that throws ends with internal error', () async {
      final h = Harness(
        primary: ProviderTarget(
          profileId: 'x',
          modelId: 'm',
          provider: ThrowingProvider(),
          privacy: PrivacyLevel.standard,
        ),
      );
      final failed = terminal(await h.run('x')) as AgentFailed;
      expect(failed.error, AgentErrorKind.internal);
    });
  });
}
