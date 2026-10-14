// Unit tests of the run's parts without the loop: RunBudget, RunState and
// PrivacyScope (src-internal, see `lib/src/run/`).

import 'package:test/test.dart';
import 'package:wendelin_agent/src/run/escalation.dart';
import 'package:wendelin_agent/src/run/privacy_scope.dart';
import 'package:wendelin_agent/src/run/run_budget.dart';
import 'package:wendelin_agent/src/run/run_state.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

Resolution _resolution(PrivacyLevel privacy, {PrivacyLevel? floor}) {
  final (target, _) = scripted('p', const [], privacy: privacy);
  return Resolution(target: target, reason: 'test', privacyFloor: floor);
}

RunState _state(PrivacyLevel privacy, {PrivacyLevel? floor}) => RunState(null)
  ..current = _resolution(privacy, floor: floor)
  ..context = AgentContext(
    systemPrompt: 'S',
    tools: const [],
    messages: [Message.user('hallo')],
  );

void main() {
  group('RunBudget', () {
    const config = AgentConfig(maxToolRounds: 2, maxTokensPerRequest: 100);

    test('round limit after maxToolRounds rounds', () {
      final budget = RunBudget(config);
      budget.onRound();
      expect(budget.roundLimitReached, isFalse);
      budget.onRound();
      expect(budget.roundLimitReached, isTrue);
    });

    test('tokens count without cache reads', () {
      final budget = RunBudget(config)
        ..onTokens(
          const Usage(
            inputTokens: 40,
            outputTokens: 40,
            cachedInputTokens: 1000,
            cacheWriteTokens: 19,
          ),
        );
      expect(budget.tokensExhausted, isFalse);
      budget.onTokens(const Usage(inputTokens: 1, outputTokens: 0));
      expect(budget.tokensExhausted, isTrue);
    });
  });

  group('RunState', () {
    test('the privacy floor only rises', () {
      final state = _state(PrivacyLevel.local, floor: PrivacyLevel.tee);
      state.raiseFloor(PrivacyLevel.eu);
      expect(state.current.privacyFloor, PrivacyLevel.tee);
      state.raiseFloor(PrivacyLevel.local);
      expect(state.current.privacyFloor, PrivacyLevel.local);
    });
  });

  group('PrivacyScope', () {
    PrivacyScope scope(RunState state) {
      final (primary, _) = scripted('p', const []);
      return PrivacyScope(Harness(primary: primary).runner, state);
    }

    test('content above the target level is hidden', () {
      final privacy = scope(_state(PrivacyLevel.eu));
      expect(privacy.hiddenFor(null), isFalse);
      expect(privacy.hiddenFor(PrivacyLevel.eu), isFalse);
      expect(privacy.hiddenFor(PrivacyLevel.tee), isTrue);
    });

    test('consent below the floor uncovers content up to the floor', () {
      final privacy = scope(
        _state(PrivacyLevel.standard, floor: PrivacyLevel.tee),
      )..consented(belowFloor: true);
      expect(privacy.hiddenFor(PrivacyLevel.tee), isFalse);
      expect(privacy.hiddenFor(PrivacyLevel.local), isTrue);
    });

    test('a declined consent stands', () {
      final privacy = scope(_state(PrivacyLevel.standard));
      expect(privacy.consentDeclined, isFalse);
      privacy.declined();
      expect(privacy.consentDeclined, isTrue);
    });

    test('visible private content raises the floor to its level', () {
      final state = _state(PrivacyLevel.local);
      state.messages.add(
        Message.user('privat').withPrivacyFloor(PrivacyLevel.tee),
      );
      scope(state).raiseFloorToTaint();
      expect(state.current.privacyFloor, PrivacyLevel.tee);
    });

    test('hidden private content does not taint the run', () {
      final state = _state(PrivacyLevel.standard);
      state.messages.add(
        Message.user('privat').withPrivacyFloor(PrivacyLevel.tee),
      );
      scope(state).raiseFloorToTaint();
      expect(state.current.privacyFloor, isNull);
    });
  });

  group('Escalation', () {
    test('a target change after the first model call is a bug (K28)', () {
      final (primary, _) = scripted('p', const []);
      final state = _state(PrivacyLevel.standard)..modelCalled = true;
      final control = _NoControl();
      final escalation = Escalation(
        DefaultProviderResolver(primary),
        state,
        PrivacyScope(Harness(primary: primary).runner, state),
        control,
      );
      expect(
        () => escalation.escalate(EscalationReason.userRequested),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}

final class _NoControl implements RunControl {
  @override
  final token = CancelToken();
  @override
  bool get segmentStreamed => false;
  @override
  void emit(AgentEvent e) {}
  @override
  void throwIfAborted() {}
}
