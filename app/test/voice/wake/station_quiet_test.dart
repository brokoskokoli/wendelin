// WP197: one check "station open and quiet hours" for both tones. The
// station runs in its own engine; only the platform channel knows it is open.

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin/station/station_providers.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_pre_roll.dart';

import '../../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../../support/test_env.dart';

void main() {
  // The test clock stands at 08:12.
  const quietNow = QuietHours(fromHour: 8, toHour: 9);
  const quietLater = QuietHours(fromHour: 22, toHour: 7);

  Future<bool> check(
    QuietHours quiet, {
    bool open = true,
    Object? error,
  }) async {
    final platform = FakeAssistantPlatform()
      ..stationIsOpen = open
      ..stationError = error;
    final c = TestEnv(
      extraOverrides: [assistantPlatformProvider.overrideWithValue(platform)],
    ).container();
    addTearDown(c.dispose);
    await c.read(stationPrefsProvider.notifier).set(StationPrefs(quiet: quiet));
    return stationQuiet(c.read);
  }

  test('Station offen in der Ruhezeit: wahr', () async {
    expect(await check(quietNow), isTrue);
  });

  test('Station offen außerhalb der Ruhezeit: falsch', () async {
    expect(await check(quietLater), isFalse);
  });

  test('Station nicht offen, Ruhezeit: falsch', () async {
    expect(await check(quietNow, open: false), isFalse);
  });

  test('Kanalfehler: falsch (Ton wie bisher) und geloggt', () async {
    final lines = <String>[];
    final saved = voiceLogSink;
    voiceLogSink = lines.add;
    addTearDown(() => voiceLogSink = saved);
    expect(await check(quietNow, error: StateError('x')), isFalse);
    expect(lines.single, contains('station-quiet-error'));
  });
}
