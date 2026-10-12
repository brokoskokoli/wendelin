import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'case_result.dart';

/// Aggregated figures of a set of case results.
@immutable
final class Summary {
  const Summary._({
    required this.total,
    required this.passed,
    required this.failed,
    required this.errors,
    required this.skipped,
    required this.latencyP50,
    required this.latencyP90,
    required this.usage,
    required this.costMicros,
    required this.unpricedCases,
    required this.gaveUp,
    required this.escalated,
  });

  /// Aggregates [results] (skipped cases only count in [skipped]).
  factory Summary.of(Iterable<CaseResult> results) {
    final ran = results.where((r) => r.ran).toList();
    final latencies = [for (final r in ran) r.observation.latency];
    var usage = Usage.zero;
    var cost = 0;
    var unpriced = 0;
    for (final r in ran) {
      usage = usage + r.observation.usage;
      final c = r.observation.costMicros;
      if (c == null) {
        unpriced++;
      } else {
        cost += c;
      }
    }
    int count(CaseStatus s) => ran.where((r) => r.status == s).length;
    return Summary._(
      total: ran.length,
      passed: count(CaseStatus.passed),
      failed: count(CaseStatus.failed),
      errors: count(CaseStatus.error),
      skipped: results.length - ran.length,
      latencyP50: percentile(latencies, 50),
      latencyP90: percentile(latencies, 90),
      usage: usage,
      costMicros: cost,
      unpricedCases: unpriced,
      gaveUp: ran.where((r) => r.observation.gaveUp).length,
      escalated: ran.where((r) => r.observation.escalations.isNotEmpty).length,
    );
  }

  /// Cases run.
  final int total;

  /// Cases passed.
  final int passed;

  /// Cases failed (expectation not met).
  final int failed;

  /// Cases whose agent run failed.
  final int errors;

  /// Cases skipped.
  final int skipped;

  /// Median latency (`null` without cases).
  final Duration? latencyP50;

  /// 90th percentile latency.
  final Duration? latencyP90;

  /// Summed usage.
  final Usage usage;

  /// Summed cost of priced cases in micro-USD.
  final int costMicros;

  /// Cases without a known price (cost incomplete if > 0).
  final int unpricedCases;

  /// Cases in which the model gave up („kann ich nicht“).
  final int gaveUp;

  /// Cases with at least one escalation.
  final int escalated;

  /// Share of passed cases among those run (0–1; 0 without cases).
  double get passRate => total == 0 ? 0 : passed / total;

  /// JSON for the report.
  Map<String, Object?> toJson() => {
    'total': total,
    'passed': passed,
    'failed': failed,
    'errors': errors,
    'skipped': skipped,
    'passRate': double.parse(passRate.toStringAsFixed(4)),
    'latencyMs': {
      'p50': latencyP50?.inMilliseconds,
      'p90': latencyP90?.inMilliseconds,
    },
    'usage': {
      'input': usage.inputTokens,
      'output': usage.outputTokens,
      'cacheRead': usage.cachedInputTokens,
      'cacheWrite': usage.cacheWriteTokens,
      'total': usage.totalTokens,
    },
    'costMicros': costMicros,
    'costUsd': double.parse((costMicros / 1e6).toStringAsFixed(6)),
    'unpricedCases': unpricedCases,
    'gaveUp': gaveUp,
    'escalated': escalated,
  };
}

/// Summary of all results plus one per language.
Map<String, Summary> summariesByLanguage(Iterable<CaseResult> results) {
  final langs = results.map((r) => r.evalCase.language).toSet().toList()
    ..sort();
  return {
    for (final l in langs)
      l: Summary.of(results.where((r) => r.evalCase.language == l)),
  };
}

/// Nearest-rank percentile [p] (0–100] of [values]; `null` if empty.
Duration? percentile(List<Duration> values, num p) {
  if (values.isEmpty) return null;
  if (p <= 0 || p > 100) {
    throw ArgumentError.value(p, 'p', 'muss in (0, 100] liegen');
  }
  final sorted = List.of(values)..sort();
  final rank = (p / 100 * sorted.length).ceil();
  return sorted[rank - 1];
}
