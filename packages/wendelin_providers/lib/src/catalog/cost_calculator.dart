import 'package:wendelin_core/wendelin_core.dart';

import 'model_catalog.dart';

/// Computes request costs from [Usage] and a [ModelCatalog].
final class CostCalculator {
  /// Creates a calculator for [catalog].
  const CostCalculator(this.catalog);

  /// Price source.
  final ModelCatalog catalog;

  /// Cost of [usage] on [modelId] in micro-USD (rounded half up), or `null`
  /// if the model is not in the catalog (unknown cost, not zero).
  ///
  /// [usage] must be the usage of **one** model call (sum of its
  /// `UsageEvent`s): the long-context tier applies when that call's input
  /// tokens (uncached, cache read and cache write) exceed the model's
  /// threshold. Summing several calls first would apply the tier wrongly;
  /// add the per-call costs instead.
  ///
  /// Known gap: fees per server-side tool use (e.g. Anthropic web search,
  /// billed per search) are not included, because `Usage` has no field
  /// for them.
  int? costMicros(String modelId, Usage usage) {
    final entry = catalog.lookup(modelId);
    if (entry == null) return null;
    final prompt =
        usage.inputTokens + usage.cachedInputTokens + usage.cacheWriteTokens;
    final p = entry.priceFor(prompt);
    final scaled =
        usage.inputTokens * p.input +
        usage.outputTokens * p.output +
        usage.cachedInputTokens * p.cacheRead +
        usage.cacheWriteTokens * p.cacheWrite;
    return (scaled + 500000) ~/ 1000000;
  }
}
