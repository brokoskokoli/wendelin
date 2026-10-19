/// Counters of one agent run against the limits of [AgentConfig]: tool
/// rounds, tokens and the monthly budget warning. Internal to `wendelin_agent`, not exported.
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
final class RunBudget {
  /// Creates the budget for [config].
  RunBudget(this._config);

  final AgentConfig _config;

  int _rounds = 0;
  int _tokensSpent = 0;
  final Set<String> _warned = {};

  /// No further tool round is allowed in this run.
  bool get roundLimitReached => _rounds >= _config.maxToolRounds;

  /// The token budget of the request is used up.
  bool get tokensExhausted => _tokensSpent >= _config.maxTokensPerRequest;

  /// Counts a tool round.
  void onRound() => _rounds++;

  /// Counts the tokens of one model call.
  void onTokens(Usage used) {
    // Cache reads are cheap and do not count towards the run budget.
    _tokensSpent +=
        used.inputTokens + used.outputTokens + used.cacheWriteTokens;
  }

  /// Adds the tokens of [other], a budget that an overlapping
  /// call (WP81b) counted on its own; only a kept call is absorbed.
  void absorb(RunBudget other) => _tokensSpent += other._tokensSpent;

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
