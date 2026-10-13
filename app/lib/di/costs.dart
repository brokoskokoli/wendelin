import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// [CostEstimator] with the prices of the model catalog.
final class CatalogCostEstimator implements CostEstimator {
  /// Creates the estimator.
  const CatalogCostEstimator(this.calculator);

  /// Price calculation.
  final CostCalculator calculator;

  @override
  int? estimateMicros({
    required String profileId,
    required String modelId,
    required Usage usage,
  }) => calculator.costMicros(modelId, usage);
}

/// [BudgetGuard] from the profile's monthly budget and the costs recorded
/// this month.
///
/// No budget → ok. Spent ≥ budget → block. Spent ≥ budget × warn threshold
/// → warn. Unknown profiles (demo) → ok.
final class RepositoryBudgetGuard implements BudgetGuard {
  /// Creates the guard.
  const RepositoryBudgetGuard({required this.profiles, required this.usage});

  /// Provider profiles with budget and threshold.
  final ProviderProfileRepository profiles;

  /// Recorded costs.
  final UsageRepository usage;

  @override
  Future<BudgetCheck> check(String profileId) async {
    final profile = await profiles.get(profileId);
    final budget = profile?.budgetMonthly;
    if (profile == null || budget == null) return BudgetCheck.ok;
    final spent = await usage.monthToDateCostMicros(profileId);
    if (spent >= budget) {
      return BudgetCheck.block(spentMicros: spent, budgetMicros: budget);
    }
    final threshold = profile.warnThreshold;
    if (threshold != null && spent >= budget * threshold) {
      return BudgetCheck.warn(spentMicros: spent, budgetMicros: budget);
    }
    return BudgetCheck.ok;
  }
}

/// Cost of today (local day) over all profiles in micro-USD.
Future<int> todayCostMicros(UsageRepository usage, DateTime now) async {
  final start = DateTime(now.year, now.month, now.day);
  final days = await usage.totalsByDay(from: start);
  return days.fold<int>(0, (sum, d) => sum + d.costMicros);
}
