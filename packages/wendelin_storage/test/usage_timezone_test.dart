import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Day and month totals and the budget month use the device's local time.
/// Runs a helper process under fixed time zones, so a fallback to UTC is
/// caught regardless of the time zone the tests run in.
void main() {
  Future<Map<String, Object?>> probe(String tz) async {
    final r = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'test/support/usage_timezone_probe.dart'],
      environment: {'TZ': tz},
    );
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final line = (r.stdout as String).trim().split('\n').last;
    return jsonDecode(line) as Map<String, Object?>;
  }

  test('Asia/Kolkata (UTC+5:30)', () async {
    final p = await probe('Asia/Kolkata');
    expect(p['offsetMinutes'], 330, reason: 'TZ wurde nicht übernommen');
    expect(p['days'], [
      ['2026-10-14T00:00:00.000', 7],
      ['2026-11-01T00:00:00.000', 24],
    ]);
    expect(p['months'], [
      ['2026-10-01T00:00:00.000', 7],
      ['2026-11-01T00:00:00.000', 24],
    ]);
    expect(p['monthToDate'], 24);
  });

  test('America/Los_Angeles (UTC-7)', () async {
    final p = await probe('America/Los_Angeles');
    expect(p['offsetMinutes'], -420, reason: 'TZ wurde nicht übernommen');
    expect(p['days'], [
      ['2026-10-13T00:00:00.000', 7],
      ['2026-10-31T00:00:00.000', 24],
    ]);
    expect(p['months'], [
      ['2026-10-01T00:00:00.000', 31],
    ]);
    expect(p['monthToDate'], 31);
  });
}
