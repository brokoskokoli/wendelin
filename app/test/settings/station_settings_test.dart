import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin/station/station_providers.dart';
import 'package:wendelin/ui/settings/station_screen.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart' show settle;
import 'lists_and_web_test.dart' show pumpPage;

void main() {
  testWidgets('Bildschirmmodus, Ruhezeit und Bereiche werden gespeichert', (
    tester,
  ) async {
    final env = TestEnv();
    final c = await pumpPage(tester, env, const StationSettingsScreen());
    expect(c.read(stationPrefsProvider), const StationPrefs());

    await tester.tap(find.text('Tagsüber an, in den Ruhezeiten aus'));
    await settle(tester);
    expect(
      c.read(stationPrefsProvider).screenMode,
      StationScreenMode.daytimeOnly,
    );

    await tester.tap(find.byKey(const ValueKey('section-events')));
    await settle(tester);
    expect(c.read(stationPrefsProvider).hidden, {StationSection.events});
    await tester.tap(find.byKey(const ValueKey('section-events')));
    await settle(tester);
    expect(c.read(stationPrefsProvider).hidden, isEmpty);
    await tester.tap(find.byKey(const ValueKey('section-tasks')));
    await settle(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('quietFrom')),
        matching: find.byType(DropdownButton<int>),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('23 Uhr').last);
    await settle(tester);

    final stored = await env.storage.settings.get(AppSettings.station);
    expect(stored!.screenMode, StationScreenMode.daytimeOnly);
    expect(stored.quiet, const QuietHours(fromHour: 23, toHour: 7));
    expect(stored.hidden, {StationSection.tasks});
  });
}
