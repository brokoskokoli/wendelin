import 'package:meta/meta.dart';

/// Token usage of one or more model calls. Combine with [operator +].
@immutable
final class Usage {
  /// Creates a usage record; all counts default to 0.
  const Usage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cachedInputTokens = 0,
    this.cacheWriteTokens = 0,
  });

  /// No usage.
  static const zero = Usage();

  /// Uncached input tokens.
  final int inputTokens;

  /// Generated tokens.
  final int outputTokens;

  /// Input tokens served from the provider's prompt cache (cache read).
  final int cachedInputTokens;

  /// Input tokens written to the provider's prompt cache.
  final int cacheWriteTokens;

  /// Sum of all four counts.
  int get totalTokens =>
      inputTokens + outputTokens + cachedInputTokens + cacheWriteTokens;

  /// Field-wise sum.
  Usage operator +(Usage other) => Usage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    cachedInputTokens: cachedInputTokens + other.cachedInputTokens,
    cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
  );

  @override
  bool operator ==(Object other) =>
      other is Usage &&
      other.inputTokens == inputTokens &&
      other.outputTokens == outputTokens &&
      other.cachedInputTokens == cachedInputTokens &&
      other.cacheWriteTokens == cacheWriteTokens;

  @override
  int get hashCode => Object.hash(
    inputTokens,
    outputTokens,
    cachedInputTokens,
    cacheWriteTokens,
  );

  @override
  String toString() =>
      'Usage(in: $inputTokens, out: $outputTokens, '
      'cacheRead: $cachedInputTokens, cacheWrite: $cacheWriteTokens)';
}
