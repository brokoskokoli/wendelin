// Agent loop budgets: tokens and monthly budget guard.

import 'package:test/test.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
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

    test('cache reads do not count towards the token budget', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('c1', 'web__search'),
        ], usage: const Usage(inputTokens: 10, cachedInputTokens: 1000)),
        ScriptedTurn.text('ok'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
        config: const AgentConfig(maxTokensPerRequest: 100),
      );
      expect(terminal(await h.run('x')), isA<AgentDone>());
    });

    test('cache writes count towards the token budget', () async {
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([
          call('c1', 'web__search'),
        ], usage: const Usage(cacheWriteTokens: 100)),
        ScriptedTurn.text('nie'),
      ]);
      final h = Harness(
        primary: a,
        tools: [FakeTool(name: 'web__search')],
        config: const AgentConfig(maxTokensPerRequest: 100),
      );
      final failed = terminal(await h.run('x')) as AgentFailed;
      expect(failed.error, AgentErrorKind.tokenBudget);
    });

    test('budget guard blocks before any model call', () async {
      final (a, provider) = scripted('a', [ScriptedTurn.text('nie')]);
      final guard = FixedBudgetGuard(
        const BudgetCheck.block(spentMicros: 11, budgetMicros: 10),
      );
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
        budget: FixedBudgetGuard(
          const BudgetCheck.warn(spentMicros: 9, budgetMicros: 10),
        ),
      );
      expect(terminal(await h.run('x')), isA<AgentDone>());
    });
  });
}
