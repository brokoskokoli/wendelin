/// Counters of one agent run against the limits of [AgentConfig]: tool
/// rounds, rounds and invalid calls per provider, tokens and the monthly
/// budget warning. Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import '../agent_config.dart';
import '../ports.dart';
import '../provider_resolver.dart';
import 'run_state.dart';

/// Budget of one run.
///
/// Invariants:
/// - [roundLimitReached] holds after `maxToolRounds` rounds, so the loop
///   refuses round `maxToolRounds + 1` (default: the 9th).
/// - Cache reads never count towards the tokens ([onTokens]).
/// - The per-provider counters ([noProgress], [tooManyInvalid]) start fresh
///   after every hand-over ([onEscalated]); the run-wide ones do not.
final class RunBudget {
  /// Creates the budget for [config].
  RunBudget(this._config);

  final AgentConfig _config;

  int _rounds = 0;
  int _roundsOnProvider = 0;
  int _invalidOnProvider = 0;
  int _tokensSpent = 0;
  final Set<String> _warned = {};

  /// No further tool round is allowed in this run.
  bool get roundLimitReached => _rounds >= _config.maxToolRounds;

  /// The token budget of the request is used up.
  bool get tokensExhausted => _tokensSpent >= _config.maxTokensPerRequest;

  /// The current provider had enough rounds without a final answer.
  bool get noProgress =>
      _roundsOnProvider >= _config.escalateAfterRoundsWithoutResult;

  /// The current provider made enough invalid tool calls.
  bool get tooManyInvalid =>
      _invalidOnProvider >= _config.escalateAfterInvalidToolCalls;

  /// Counts a tool round (run-wide and for the current provider).
  void onRound() {
    _rounds++;
    _roundsOnProvider++;
  }

  /// Counts the tokens of one model call.
  void onTokens(Usage used) {
    // Cache reads are cheap and do not count towards the run budget.
    _tokensSpent +=
        used.inputTokens + used.outputTokens + used.cacheWriteTokens;
  }

  /// Counts [count] invalid tool calls of the current provider.
  void onInvalidCalls(int count) => _invalidOnProvider += count;

  /// A hand-over to another target happened.
  void onEscalated() {
    // Invariant: counters per provider start fresh at the new provider.
    _roundsOnProvider = 0;
    _invalidOnProvider = 0;
  }

  /// Checks the monthly budget of [target]'s profile with [guard]: throws
  /// [RunStop] when it is blocked, warns once per run and profile.
  Future<void> checkGuard(
    BudgetGuard? guard,
    Resolution target,
    RunControl control,
  ) async {
    final profileId = target.profileId;
    final budget = await guard?.check(profileId);
    switch (budget?.status) {
      case BudgetStatus.block:
        throw RunStop(failedEvent(AgentErrorKind.budgetBlocked, _config));
      case BudgetStatus.warn when _warned.add(profileId):
        control.emit(
          BudgetWarning(
            profileId: profileId,
            spentMicros: budget!.spentMicros,
            budgetMicros: budget.budgetMicros,
          ),
        );
      case _:
        break;
    }
  }
}
