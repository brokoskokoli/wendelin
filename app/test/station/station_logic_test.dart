import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/station/station_display.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin/station/station_providers.dart';

import 'station_support.dart';

DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 20, h, m);

void main() {
  group('Ruhezeit', () {
    test('Standard 22 bis 7 Uhr reicht über Mitternacht', () {
      const q = QuietHours();
      expect(q.contains(at(21, 59)), isFalse);
      expect(q.contains(at(22)), isTrue);
      expect(q.contains(at(3)), isTrue);
      expect(q.contains(at(6, 59)), isTrue);
      expect(q.contains(at(7)), isFalse);
    });

    test('Zeitraum am selben Tag und gleiche Stunden (keine Ruhezeit)', () {
      const day = QuietHours(fromHour: 13, toHour: 15);
      expect(day.contains(at(13)), isTrue);
      expect(day.contains(at(15)), isFalse);
      expect(const QuietHours(fromHour: 5, toHour: 5).contains(at(5)), isFalse);
    });
  });

  test('Einstellungen: Rundreise, falsche Werte fallen auf Standard', () {
    const prefs = StationPrefs(
      screenMode: StationScreenMode.daytimeOnly,
      quiet: QuietHours(fromHour: 23, toHour: 6),
      hidden: {StationSection.events, StationSection.tasks},
    );
    final back = StationPrefs.fromJson(prefs.toJson());
    expect(back.screenMode, StationScreenMode.daytimeOnly);
    expect(back.quiet, const QuietHours(fromHour: 23, toHour: 6));
    expect(back.hidden, {StationSection.events, StationSection.tasks});
    final junk = StationPrefs.fromJson({
      'screenMode': 'x',
      'quietFrom': 99,
      'hidden': ['nope'],
    });
    expect(junk.screenMode, StationScreenMode.alwaysDimmed);
    expect(junk.quiet, const QuietHours());
    expect(junk.hidden, isEmpty);
  });

  group('Bildschirmplan', () {
    StationDisplay plan(
      StationScreenMode m, {
      bool quiet = false,
      bool awake = false,
    }) => planDisplay(mode: m, quiet: quiet, awake: awake);

    test('immer an, gedimmt: Bildschirm an, in der Ruhezeit fast schwarz', () {
      final day = plan(StationScreenMode.alwaysDimmed);
      expect(day.keepOn, isTrue);
      expect(day.brightness, StationBrightness.ambient);
      final night = plan(StationScreenMode.alwaysDimmed, quiet: true);
      expect(night.keepOn, isTrue);
      expect(night.brightness, StationBrightness.quiet);
      expect(
        plan(
          StationScreenMode.alwaysDimmed,
          quiet: true,
          awake: true,
        ).brightness,
        StationBrightness.ambient,
      );
    });

    test('Wake Word oder Berührung: nur wach gehalten, wenn berührt', () {
      expect(plan(StationScreenMode.touchOnly).keepOn, isFalse);
      expect(plan(StationScreenMode.touchOnly, awake: true).keepOn, isTrue);
    });

    test('tagsüber an: in der Ruhezeit aus, Berührung weckt', () {
      expect(plan(StationScreenMode.daytimeOnly).keepOn, isTrue);
      expect(plan(StationScreenMode.daytimeOnly, quiet: true).keepOn, isFalse);
      expect(
        plan(StationScreenMode.daytimeOnly, quiet: true, awake: true).keepOn,
        isTrue,
      );
    });
  });

  group('Steuerung mit virtueller Uhr', () {
    test('Wechsel in die Ruhezeit schaltet Bildschirm und Helligkeit um', () {
      fakeAsync((async) {
        final clock = MutableClock(at(21, 40));
        final host = FakeStationHost();
        final c = stationContainer(
          clock: clock,
          host: host,
          prefs: const StationPrefs(screenMode: StationScreenMode.daytimeOnly),
        );
        c.listen(stationControllerProvider, (_, _) {});
        async.flushMicrotasks();
        expect(host.last!.keepOn, isTrue);
        expect(host.last!.brightness, StationBrightness.ambient);

        // 20 Minuten später, über die 30-s-Takte.
        for (var i = 0; i < 40; i++) {
          clock.time = clock.time.add(stationTick);
          async.elapse(stationTick);
        }
        expect(c.read(stationControllerProvider).now.hour, 22);
        expect(host.last!.keepOn, isFalse);
        expect(host.last!.brightness, StationBrightness.quiet);

        // Morgens um 7 Uhr wieder an.
        clock.time = at(7);
        async.elapse(stationTick);
        expect(host.last!.keepOn, isTrue);
        expect(host.last!.brightness, StationBrightness.ambient);
        c.dispose();
      });
    });

    test('Berührung weckt für 30 Sekunden, dann wieder wie vorher', () {
      fakeAsync((async) {
        final clock = MutableClock(at(12));
        final host = FakeStationHost();
        final c = stationContainer(
          clock: clock,
          host: host,
          prefs: const StationPrefs(screenMode: StationScreenMode.touchOnly),
        );
        c.listen(stationControllerProvider, (_, _) {});
        async.flushMicrotasks();
        expect(host.last!.keepOn, isFalse);

        c.read(stationControllerProvider.notifier).touch();
        expect(host.last!.keepOn, isTrue);

        clock.time = clock.time.add(stationAwakeFor);
        async.elapse(stationAwakeFor);
        expect(host.last!.keepOn, isFalse);
        c.dispose();
      });
    });

    test('Einstellung ändert den Plan sofort', () async {
      final host = FakeStationHost();
      final c = stationContainer(clock: MutableClock(at(12)), host: host);
      c.listen(stationControllerProvider, (_, _) {});
      await Future.microtask(() {});
      expect(host.last!.keepOn, isTrue);
      c.read(stationPrefsProvider.notifier).state = const StationPrefs(
        screenMode: StationScreenMode.touchOnly,
      );
      expect(host.last!.keepOn, isFalse);
      c.dispose();
    });
  });

  group('Beenden', () {
    late FakeStationHost host;
    late ProviderContainer c;

    setUp(() {
      host = FakeStationHost();
      c = stationContainer(clock: MutableClock(at(12)), host: host);
      c.listen(stationControllerProvider, (_, _) {});
    });

    tearDown(() => c.dispose());

    test('ohne Entsperren (Abbruch) bleibt die Station an', () async {
      host.unlockAnswers = [false];
      final ended = await c.read(stationControllerProvider.notifier).end();
      expect(ended, isFalse);
      expect(host.unlockRequests, 1);
      expect(host.finishes, 0);
      expect(c.read(stationControllerProvider).ended, isFalse);
      expect(c.read(stationControllerProvider).ending, isFalse);
    });

    test('erst nach erfolgreichem Entsperren wird beendet', () async {
      host.unlockAnswers = [true];
      final ended = await c.read(stationControllerProvider.notifier).end();
      expect(ended, isTrue);
      expect(host.finishes, 1);
      expect(c.read(stationControllerProvider).ended, isTrue);
    });

    test('Abstecken, Sprachbefehl und Wecken beenden nichts', () async {
      // Nichts außer end() erreicht finish: Berührung, Takt, dunkler Raum.
      c.read(stationControllerProvider.notifier).touch();
      host.dark.add(true);
      await Future.microtask(() {});
      expect(host.finishes, 0);
      expect(host.unlockRequests, 0);
      expect(c.read(stationControllerProvider).ended, isFalse);
    });

    test(
      'zweites Tippen während der Anfrage fragt nicht noch einmal',
      () async {
        host.unlockAnswers = [true];
        final n = c.read(stationControllerProvider.notifier);
        final first = n.end();
        expect(await n.end(), isFalse);
        expect(await first, isTrue);
        expect(host.unlockRequests, 1);
      },
    );
  });
}
