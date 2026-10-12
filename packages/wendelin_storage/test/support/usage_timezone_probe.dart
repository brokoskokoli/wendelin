// Helper process for usage_timezone_test.dart: runs under a given TZ and
// prints the usage totals as JSON. Not a test itself.
import 'dart:convert';
import 'dart:io';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

Future<void> main() async {
  // The clock deliberately returns a UTC DateTime.
  final storage = openInMemoryStorage(
    clock: FixedClock(DateTime.utc(2026, 10, 31, 20)),
  );
  final records = [
    (DateTime.utc(2026, 10, 13, 20), 1),
    (DateTime.utc(2026, 10, 13, 23, 30), 2),
    (DateTime.utc(2026, 10, 14, 1), 4),
    (DateTime.utc(2026, 10, 31, 19), 8),
    (DateTime.utc(2026, 10, 31, 21), 16),
  ];
  for (final (at, cost) in records) {
    await storage.usage.record(
      sessionId: 's',
      profileId: 'p',
      modelId: 'm',
      usage: Usage.zero,
      costMicros: cost,
      at: at,
    );
  }
  List<List<Object>> rows(List<UsageTotals> t) => [
    for (final x in t) [x.periodStart.toIso8601String(), x.costMicros],
  ];
  stdout.writeln(
    jsonEncode({
      'offsetMinutes': DateTime(2026, 10, 13).timeZoneOffset.inMinutes,
      'days': rows(await storage.usage.totalsByDay()),
      'months': rows(await storage.usage.totalsByMonth()),
      'monthToDate': await storage.usage.monthToDateCostMicros('p'),
    }),
  );
  await storage.close();
}
