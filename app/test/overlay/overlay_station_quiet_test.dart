// WP197: the overlay plays no confirmation tone at a wake word hit while the
// station is open in its quiet hours (the station runs in another engine).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin_core/testing.dart';

import '../support/test_env.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

void main() {
  // The test clock stands at 08:12.
  Future<int> plays(
    WidgetTester tester, {
    required bool stationOpen,
    required QuietHours quiet,
  }) async {
    var n = 0;
    final platform = FakeAssistantPlatform()
      ..stationIsOpen = stationOpen
      ..wakeHandoff = Int16List.fromList(List.filled(8000, 300));
    final env = TestEnv(
      startup: StartupSettings(station: StationPrefs(quiet: quiet)),
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
    );
    await tester.runAsync(() => env.storage.settings.set(wakeToneKey, true));
    await pumpOverlay(
      tester,
      env,
      platform,
      extra: [wakeConfirmToneProvider.overrideWithValue(() async => n++)],
    );
    await tester.pump(const Duration(milliseconds: 60));
    return n;
  }

  testWidgets('Station offen in der Ruhezeit: kein Ton', (tester) async {
    expect(
      await plays(
        tester,
        stationOpen: true,
        quiet: const QuietHours(fromHour: 8, toHour: 9),
      ),
      0,
    );
  });

  testWidgets('Station offen außerhalb der Ruhezeit: Ton', (tester) async {
    expect(
      await plays(
        tester,
        stationOpen: true,
        quiet: const QuietHours(fromHour: 22, toHour: 7),
      ),
      1,
    );
  });

  testWidgets('Ruhezeit ohne offene Station: Ton', (tester) async {
    expect(
      await plays(
        tester,
        stationOpen: false,
        quiet: const QuietHours(fromHour: 8, toHour: 9),
      ),
      1,
    );
  });
}
