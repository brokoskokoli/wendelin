import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Token usage and cost of one model call (or agent run).
@immutable
final class UsageRecord {
  /// Creates a record.
  const UsageRecord({
    required this.id,
    required this.at,
    required this.sessionId,
    required this.profileId,
    required this.modelId,
    required this.usage,
    required this.costMicros,
  });

  /// Database id.
  final int id;

  /// When the usage occurred.
  final DateTime at;

  /// Session of the request.
  final String sessionId;

  /// Provider profile used.
  final String profileId;

  /// Model used.
  final String modelId;

  /// Token counts (all four counters of core [Usage]).
  final Usage usage;

  /// Cost in micro-USD.
  final int costMicros;

  @override
  bool operator ==(Object other) =>
      other is UsageRecord &&
      other.id == id &&
      other.at == at &&
      other.sessionId == sessionId &&
      other.profileId == profileId &&
      other.modelId == modelId &&
      other.usage == usage &&
      other.costMicros == costMicros;

  @override
  int get hashCode =>
      Object.hash(id, at, sessionId, profileId, modelId, usage, costMicros);

  @override
  String toString() => 'UsageRecord($id, $profileId/$modelId, $costMicros µ\$)';
}

/// Summed usage of one period (day or month).
@immutable
final class UsageTotals {
  /// Creates totals.
  const UsageTotals({
    required this.periodStart,
    required this.usage,
    required this.costMicros,
    required this.count,
  });

  /// Local start of the period (midnight of the day, or the 1st of the
  /// month).
  final DateTime periodStart;

  /// Summed token counts.
  final Usage usage;

  /// Summed cost in micro-USD.
  final int costMicros;

  /// Number of records.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is UsageTotals &&
      other.periodStart == periodStart &&
      other.usage == usage &&
      other.costMicros == costMicros &&
      other.count == count;

  @override
  int get hashCode => Object.hash(periodStart, usage, costMicros, count);

  @override
  String toString() =>
      'UsageTotals($periodStart, $usage, $costMicros µ\$, n=$count)';
}
