// Agent loop: scenarios (tools, confirmations, limits, cancel) and robustness.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  group('scenarios', () {
    test('plain text answer', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('Hallo Mia.')]);
      final h = Harness(primary: a, cost: const FlatCostEstimator());
      final events = await h.run('Hallo');

      expect(events.first, isA<Routed>());
      final routed = events.first as Routed;
      expect(
        (routed.profileId, routed.modelId, routed.reason),
        ('a', 'a-model', 'Standard'),
      );
      expect(streamedText(events), 'Hallo Mia.');
      final usage = events.whereType<UsageReported>().single;
      expect(usage.usage, ScriptedTurn.defaultUsage);
      expect(usage.profileId, 'a');
      expect(usage.modelId, 'a-model');
      expect(usage.costMicros, 200); // 100 in × 1 + 20 out × 5
      final done = terminal(events) as AgentDone;
      expect(done.finalText, 'Hallo Mia.');
      expect(done.stopReason, StopReason.endTurn);

      final req = provider.requests.single;
      expect(req.model, 'a-model');
      expect(req.maxTokens, 1024);
      expect(req.systemPrompt, contains('Du bist Wendelin'));
      expect(req.messages, [Message.user('Hallo')]);
      expect(req.metadata, {'sessionId': 's1'});
      expect(h.conversation.messages, [
        Message.user('Hallo'),
        Message.assistantText('Hallo Mia.'),
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
      expect(failed.message, isNot(contains('Runde')));
      expect(failed.message, contains('technischen Fehler'));
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

    test('time limit via clock at exactly maxDuration', () async {
      late Harness h;
      final slow = FakeTool(
        name: 'web__search',
        handler: (args, ctx) {
          h.clock.advance(const Duration(seconds: 60));
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
    });

    test('just under maxDuration the run continues', () async {
      late Harness h;
      final slow = FakeTool(
        name: 'web__search',
        handler: (args, ctx) {
          h.clock.advance(const Duration(seconds: 59));
          return ToolOutcome.text('knapp');
        },
      );
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'web__search')]),
        ScriptedTurn.text('Geschafft.'),
      ]);
      h = Harness(primary: a, tools: [slow]);
      expect(terminal(await h.run('x')), isA<AgentDone>());
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

    test('the next run may start from the terminal event', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.text('eins'),
        ScriptedTurn.text('zwei'),
      ]);
      final h = Harness(primary: a);
      final second = Completer<List<AgentEvent>>();
      h.runner.run(UserInput(text: '1')).listen((e) {
        if (e is AgentDone) {
          second.complete(h.runner.run(UserInput(text: '2')).toList());
        }
      });
      final events = await second.future;
      expect((terminal(events) as AgentDone).finalText, 'zwei');
      expect(provider.requests, hasLength(2));
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

  group('robustness', () {
    test('results reach the model in call order, not finish order', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('c1', 'web__search', '{"n":1}'),
          call('c2', 'web__search', '{"n":2}'),
        ]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
        invoker: ReversedInvoker(),
      );
      final events = await h.run('x');
      expect(events.whereType<ToolCallFinished>().map((e) => e.call.id), [
        'c2',
        'c1',
      ]);
      expect(lastResults(provider.requests[1]).map((r) => r.callId), [
        'c1',
        'c2',
      ]);
      expect(
        lastResults(provider.requests[1])
            .map((r) => (r.content.single as TextBlock).text),
        ['Ergebnis c1', 'Ergebnis c2'],
      );
    });

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
