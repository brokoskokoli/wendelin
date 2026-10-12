import 'package:drift/drift.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../model/usage_record.dart';
import '../repositories/repositories.dart';
import 'database.dart';

/// drift implementation of [UsageRepository].
final class DriftUsageRepository implements UsageRepository {
  /// Creates the repository.
  DriftUsageRepository(this._db, this._clock);

  final WendelinDatabase _db;
  final Clock _clock;

  @override
  Future<UsageRecord> record({
    required String sessionId,
    required String profileId,
    required String modelId,
    required Usage usage,
    required int costMicros,
    DateTime? at,
  }) async {
    final when = at ?? _clock.now();
    final id = await _db
        .into(_db.usageRecords)
        .insert(
          UsageRecordsCompanion.insert(
            at: when,
            sessionId: sessionId,
            profileId: profileId,
            modelId: modelId,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cachedTokens: usage.cachedInputTokens,
            cacheWriteTokens: usage.cacheWriteTokens,
            costMicros: costMicros,
          ),
        );
    return UsageRecord(
      id: id,
      at: when,
      sessionId: sessionId,
      profileId: profileId,
      modelId: modelId,
      usage: usage,
      costMicros: costMicros,
    );
  }

  @override
  Future<List<UsageTotals>> totalsByDay({
    String? profileId,
    DateTime? from,
    DateTime? until,
  }) => _totals(
    profileId,
    from,
    until,
    (at) => DateTime(at.year, at.month, at.day),
  );

  @override
  Future<List<UsageTotals>> totalsByMonth({
    String? profileId,
    DateTime? from,
    DateTime? until,
  }) => _totals(profileId, from, until, (at) => DateTime(at.year, at.month));

  @override
  Future<int> monthToDateCostMicros(String profileId) async {
    // The clock may return UTC; the budget month is the local month.
    final now = _clock.now().toLocal();
    final monthStart = DateTime(now.year, now.month);
    final t = _db.usageRecords;
    final sum = t.costMicros.sum();
    final result =
        await (_db.selectOnly(t)
              ..addColumns([sum])
              ..where(
                t.profileId.equals(profileId) &
                    t.at.isBiggerOrEqualValue(
                      monthStart.microsecondsSinceEpoch,
                    ),
              ))
            .map((r) => r.read(sum))
            .getSingle();
    return result ?? 0;
  }

  Future<List<UsageTotals>> _totals(
    String? profileId,
    DateTime? from,
    DateTime? until,
    DateTime Function(DateTime at) period,
  ) async {
    final q = _db.select(_db.usageRecords)
      ..orderBy([(u) => OrderingTerm.asc(u.at)]);
    if (profileId != null) q.where((u) => u.profileId.equals(profileId));
    if (from != null) {
      q.where((u) => u.at.isBiggerOrEqualValue(from.microsecondsSinceEpoch));
    }
    if (until != null) {
      q.where((u) => u.at.isSmallerThanValue(until.microsecondsSinceEpoch));
    }
    final buckets = <DateTime, UsageTotals>{};
    for (final r in await q.get()) {
      final key = period(r.at);
      final prev = buckets[key];
      final usage = Usage(
        inputTokens: r.inputTokens,
        outputTokens: r.outputTokens,
        cachedInputTokens: r.cachedTokens,
        cacheWriteTokens: r.cacheWriteTokens,
      );
      buckets[key] = UsageTotals(
        periodStart: key,
        usage: (prev?.usage ?? Usage.zero) + usage,
        costMicros: (prev?.costMicros ?? 0) + r.costMicros,
        count: (prev?.count ?? 0) + 1,
      );
    }
    return buckets.values.toList();
  }
}
