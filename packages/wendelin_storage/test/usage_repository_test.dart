import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

void main() {
  late WendelinStorage storage;
  late FixedClock clock;
  late UsageRepository repo;

  setUp(() {
    final f = openTestStorage();
    storage = f.storage;
    clock = f.clock;
    repo = storage.usage;
  });
  tearDown(() => storage.close());

  Future<UsageRecord> rec(
    DateTime at, {
    String profile = 'claude',
    int cost = 100,
    Usage usage = const Usage(inputTokens: 10, outputTokens: 2),
  }) => repo.record(
    sessionId: 's1',
    profileId: profile,
    modelId: 'haiku',
    usage: usage,
    costMicros: cost,
    at: at,
  );

  test('record speichert alle vier Zähler und nutzt die Uhr', () async {
    const usage = Usage(
      inputTokens: 1,
      outputTokens: 2,
      cachedInputTokens: 3,
      cacheWriteTokens: 4,
    );
    final r = await repo.record(
      sessionId: 's1',
      profileId: 'claude',
      modelId: 'haiku',
      usage: usage,
      costMicros: 42,
    );
    expect(r.at, t0);
    expect(r.usage, usage);
    final day = (await repo.totalsByDay()).single;
    expect(day.usage, usage);
    expect(day.costMicros, 42);
    expect(day.count, 1);
    expect(day.periodStart, DateTime(2026, 10, 13));
  });

  test(
    'totalsByDay gruppiert nach lokalem Tag, filtert Profil und Zeitraum',
    () async {
      await rec(DateTime(2026, 10, 12, 23, 59), cost: 1);
      await rec(DateTime(2026, 10, 13, 0, 0), cost: 10);
      await rec(DateTime(2026, 10, 13, 18), cost: 20);
      await rec(DateTime(2026, 10, 13, 19), cost: 1000, profile: 'ollama');
      await rec(DateTime(2026, 10, 15, 8), cost: 300);

      final all = await repo.totalsByDay();
      expect(
        [for (final t in all) t.periodStart],
        [
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 13),
          DateTime(2026, 10, 15),
        ],
      );
      expect([for (final t in all) t.costMicros], [1, 1030, 300]);
      expect(all[1].count, 3);
      expect(all[1].usage, const Usage(inputTokens: 30, outputTokens: 6));

      final claude = await repo.totalsByDay(profileId: 'claude');
      expect([for (final t in claude) t.costMicros], [1, 30, 300]);

      final range = await repo.totalsByDay(
        from: DateTime(2026, 10, 13),
        until: DateTime(2026, 10, 15, 8),
      );
      expect([for (final t in range) t.costMicros], [1030]);
    },
  );

  test('totalsByMonth', () async {
    await rec(DateTime(2026, 9, 30, 23), cost: 5);
    await rec(DateTime(2026, 10, 1), cost: 7);
    await rec(DateTime(2026, 10, 31, 23), cost: 11);
    await rec(DateTime(2026, 10, 2), cost: 1000, profile: 'ollama');
    final months = await repo.totalsByMonth(profileId: 'claude');
    expect(months, [
      UsageTotals(
        periodStart: DateTime(2026, 9),
        usage: const Usage(inputTokens: 10, outputTokens: 2),
        costMicros: 5,
        count: 1,
      ),
      UsageTotals(
        periodStart: DateTime(2026, 10),
        usage: const Usage(inputTokens: 20, outputTokens: 4),
        costMicros: 18,
        count: 2,
      ),
    ]);
    expect(
      (await repo.totalsByMonth(from: DateTime(2026, 10))).single.costMicros,
      1018,
    );
  });

  test('monthToDateCostMicros: nur laufender Monat und Profil', () async {
    expect(await repo.monthToDateCostMicros('claude'), 0);
    await rec(DateTime(2026, 9, 30, 23, 59, 59), cost: 5);
    await rec(DateTime(2026, 10, 1), cost: 7);
    await rec(DateTime(2026, 10, 13, 8), cost: 11);
    await rec(DateTime(2026, 10, 13, 8), cost: 1000, profile: 'ollama');
    expect(await repo.monthToDateCostMicros('claude'), 18);
    expect(await repo.monthToDateCostMicros('ollama'), 1000);
    clock.set(DateTime(2026, 11, 1));
    expect(await repo.monthToDateCostMicros('claude'), 0);
  });

  test('Wertobjekte: Gleichheit und toString', () async {
    final a = await rec(t0);
    final b = await rec(t0);
    expect(a, isNot(b));
    expect(
      a,
      UsageRecord(
        id: a.id,
        at: t0,
        sessionId: 's1',
        profileId: 'claude',
        modelId: 'haiku',
        usage: const Usage(inputTokens: 10, outputTokens: 2),
        costMicros: 100,
      ),
    );
    expect(a.hashCode, isNot(b.hashCode));
    expect(a.toString(), contains('claude'));
    final t = (await repo.totalsByDay()).single;
    expect(t.toString(), contains('n=2'));
    expect(t.hashCode, (await repo.totalsByDay()).single.hashCode);
  });
}
