// Agent loop core contract: thinking, provider blocks, pause, retry, text reset.

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
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

    test('provider blocks stay in place, never in text', () async {
      const search = ProviderBlock(
        provider: 'anthropic',
        rawJson: '{"type":"server_tool_use","id":"s1"}',
        summary: 'Websuche: Wetter',
      );
      const result = ProviderBlock(
        provider: 'anthropic',
        rawJson: '{"type":"web_search_tool_result","tool_use_id":"s1"}',
      );
      final c1 = call('c1', 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.events([
          const TextDelta('Ich suche. '),
          const ProviderBlockComplete(search),
          const ProviderBlockComplete(result),
          const TextDelta('Gefunden.'),
          ToolCallComplete(c1),
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
        const TextBlock('Ich suche. '),
        search,
        result,
        const TextBlock('Gefunden.'),
        c1,
      ]);
      expect(streamedText(events), 'Ich suche. Gefunden.Fertig.');
      expect(streamedText(events), isNot(contains('server_tool_use')));
      expect(h.conversation.messages[1].content, contains(search));
    });

    test('pauseTurn ending with a provider block continues with it', () async {
      const block = ProviderBlock(
        provider: 'fake',
        rawJson: '{"type":"server_tool_use","id":"s1"}',
      );
      final (a, provider) = scripted('a', [
        ScriptedTurn.events([
          const TextDelta('Ich suche.'),
          const ProviderBlockComplete(block),
          const Done(StopReason.pauseTurn),
        ]),
        ScriptedTurn.text(' Sonnig.'),
      ]);
      final h = Harness(primary: a);
      final events = await h.run('Wetter?');
      expect(provider.requests[1].messages.last.content, [
        const TextBlock('Ich suche.'),
        block,
      ]);
      final done = terminal(events) as AgentDone;
      expect(done.finalText, 'Ich suche. Sonnig.');
      expect(h.conversation.messages[1].content.last, block);
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
      expect(failed.message, contains('Zugang abgelehnt'));
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

    test('pause segments are recorded only once the answer stands', () async {
      final recorded = <int>[];
      late Harness h;
      final (a, _) = scripted('a', [
        ScriptedTurn.text('Teil eins.', stopReason: StopReason.pauseTurn),
        ScriptedTurn.text(' Teil zwei.'),
      ]);
      h = Harness(primary: a);
      await h.run(
        'x',
        onEvent: (e) {
          if (e is AgentTextDelta) recorded.add(h.conversation.messages.length);
        },
      );
      // While the continuation streams, only the user message is stored.
      expect(recorded.last, 1);
      expect(h.conversation.messages, [
        Message.user('x'),
        Message.assistantText('Teil eins.'),
        Message.assistantText(' Teil zwei.'),
      ]);
    });

    test('retry after a pause resends the kept pause text', () async {
      final (a, provider) = scripted('a', [
        ScriptedTurn.text(
          'Teil eins.',
          stopReason: StopReason.pauseTurn,
          chunkSize: 100,
        ),
        ScriptedTurn.error(
          const NetworkException('weg'),
          partialText: ' Te',
          chunkSize: 100,
        ),
        ScriptedTurn.text(' Teil zwei.', chunkSize: 100),
      ]);
      final h = Harness(primary: a);
      final events = await h.run('x');
      expect(
        [
          for (final e in events)
            if (e is AgentTextDelta)
              e.text
            else if (e is AgentTextReset)
              'RESET',
        ],
        ['Teil eins.', ' Te', 'RESET', 'Teil eins.', ' Teil zwei.'],
      );
      // The retry keeps the pause segment as prefill for the same provider.
      expect(
        provider.requests[2].messages.last,
        Message.assistantText('Teil eins.'),
      );
      expect(
        (terminal(events) as AgentDone).finalText,
        'Teil eins. Teil zwei.',
      );
      expect(h.conversation.messages, hasLength(3));
    });

    test('tool calls in a paused answer are executed as a round', () async {
      final tool = FakeTool(name: 'web__search');
      final c1 = call('c1', 'web__search');
      final (a, provider) = scripted('a', [
        ScriptedTurn.events([
          ToolCallComplete(c1),
          const Done(StopReason.pauseTurn),
        ]),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      await h.run('x');
      expect(tool.callCount, 1);
      expect(lastResults(provider.requests[1]).single.callId, 'c1');
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

    test(
      'provider error: partial text is reset for the retry, then the run fails',
      () async {
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
        final (b, pb) = scripted('b', [ScriptedTurn.text('B.', chunkSize: 10)]);
        final events = await Harness(primary: a, chain: [b]).run('x');
        expect(pb.requests, isEmpty);
        expect(kinds(events), ['T:A1', 'RESET', 'T:A2']);
        expect(terminal(events), isA<AgentFailed>());
      },
    );

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
        ScriptedTurn.text('A.'),
      ]);
      final (b, _) = scripted('b', [ScriptedTurn.text('B.')]);
      final guard = FixedBudgetGuard(
        const BudgetCheck.warn(spentMicros: 8000000, budgetMicros: 10000000),
      );
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
        budget: guard,
      );
      final events = await h.run('x');
      final warnings = events.whereType<BudgetWarning>().toList();
      expect(warnings.map((w) => w.profileId), ['a']);
      expect(warnings.first.spentMicros, 8000000);
      expect(warnings.first.budgetMicros, 10000000);
      expect(guard.checked, ['a', 'a']);
      expect(terminal(events), isA<AgentDone>());
      // A new run warns again.
      (b.provider as FakeLlmProvider).enqueue(ScriptedTurn.text('nochmal'));
      final h2 = Harness(primary: b, budget: guard);
      final again = await h2.run('y');
      expect(again.whereType<BudgetWarning>(), hasLength(1));
    });
  });
}
