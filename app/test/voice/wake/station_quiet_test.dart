// WP197: one check "station active and quiet hours" for both tones.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin/station/station_providers.dart';
import 'package:wendelin/voice/wake/wake_pre_roll.dart';

import '../../station/station_support.dart' show FakeStationHost;
import '../../support/test_env.dart';

void main() {
  // The test clock stands at 08:12.
  const quietNow = QuietHours(fromHour: 8, toHour: 9);
  const quietLater = QuietHours(fromHour: 22, toHour: 7);

  Future<ProviderContainer> make(
    QuietHours quiet, {
    bool stationOn = true,
  }) async {
    final env = TestEnv(
      extraOverrides: [
        stationHostProvider.overrideWithValue(FakeStationHost()),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    await c.read(stationPrefsProvider.notifier).set(StationPrefs(quiet: quiet));
    if (stationOn) c.listen(stationControllerProvider, (_, _) {});
    return c;
  }

  bool check(ProviderContainer c) =>
      stationQuiet(exists: c.exists, read: c.read);

  test('Station aktiv in der Ruhezeit: wahr', () async {
    expect(check(await make(quietNow)), isTrue);
  });

  test('Station aktiv außerhalb der Ruhezeit: falsch', () async {
    expect(check(await make(quietLater)), isFalse);
  });

  test(
    'Station nicht aktiv, Ruhezeit: falsch, erzeugt keinen Zustand',
    () async {
      final c = await make(quietNow, stationOn: false);
      expect(check(c), isFalse);
      expect(c.exists(stationControllerProvider), isFalse);
    },
  );
}
