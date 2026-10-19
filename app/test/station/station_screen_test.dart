import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/l10n/l10n.dart';
import 'package:wendelin/station/station_data.dart';
import 'package:wendelin/station/station_prefs.dart';
import 'package:wendelin/station/ui/station_screen.dart';
import 'package:wendelin/ui/theme/app_theme.dart';

import '../ui/helpers.dart';
import 'station_support.dart';

final noon = DateTime(2026, 10, 20, 12, 34);

final events = [
  StationEvent(title: 'Zahnarzt Dr. Klein', start: DateTime(2026, 10, 20, 15)),
  StationEvent(
    title: 'Geburtstag Oma',
    start: DateTime(2026, 10, 21),
    allDay: true,
  ),
];
const tasks = [
  StationTask(title: 'Steuer abgeben', overdue: true),
  StationTask(title: 'Müll rausbringen'),
];

FakeStationData data() => FakeStationData(
  weatherNow: const StationWeather(
    place: 'Kiel',
    temperatureC: 13.6,
    condition: 'leicht bewölkt',
  ),
  eventList: events,
  taskList: tasks,
);

Future<(FakeStationHost, FakeStationData)> pumpStation(
  WidgetTester tester, {
  StationPrefs prefs = const StationPrefs(),
  DateTime? now,
  Key? boundary,
}) async {
  final host = FakeStationHost();
  final fake = data();
  setView(tester, const Size(390, 800));
  await tester.pumpWidget(
    ProviderScope(
      overrides: stationOverrides(
        clock: MutableClock(now ?? noon),
        host: host,
        prefs: prefs,
        data: fake,
      ),
      child: MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: wendelinLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: buildWendelinTheme(),
        home: RepaintBoundary(
          key: boundary ?? goldenKey,
          child: const StationScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (host, fake);
}

void main() {
  testWidgets('Ruhezustand zeigt Uhr, Datum, Wetter, Termine und Aufgaben mit '
      'Titeln', (tester) async {
    await pumpStation(tester);
    expect(find.text('12:34'), findsOneWidget);
    expect(find.byKey(const ValueKey('stationDate')), findsOneWidget);
    expect(find.textContaining('14 °C'), findsOneWidget);
    expect(find.textContaining('Zahnarzt Dr. Klein'), findsOneWidget);
    expect(find.textContaining('15:00'), findsOneWidget);
    expect(find.textContaining('Geburtstag Oma'), findsOneWidget);
    expect(find.text('Steuer abgeben · überfällig'), findsOneWidget);
    expect(find.text('Müll rausbringen'), findsOneWidget);
    // Platzhalter für WP100.
    expect(find.byKey(const ValueKey('stationPlaybackSlot')), findsOneWidget);
    expect(find.byKey(const ValueKey('stationTilesSlot')), findsOneWidget);
  });

  for (final (section, key, title, read)
      in <(StationSection, String, String, int Function(FakeStationData))>[
        (
          StationSection.weather,
          'stationWeather',
          '14 °C',
          (d) => d.weatherReads,
        ),
        (
          StationSection.events,
          'stationEvents',
          'Zahnarzt Dr. Klein',
          (d) => d.eventReads,
        ),
        (
          StationSection.tasks,
          'stationTasks',
          'Müll rausbringen',
          (d) => d.taskReads,
        ),
      ]) {
    testWidgets('Bereich ${section.name} aus: nicht angezeigt und gar nicht '
        'gelesen', (tester) async {
      final (_, fake) = await pumpStation(
        tester,
        prefs: StationPrefs(hidden: {section}),
      );
      expect(find.byKey(ValueKey(key)), findsNothing);
      expect(find.textContaining(title), findsNothing);
      expect(
        read(fake),
        0,
        reason: 'ein ausgeblendeter Bereich wird nicht gelesen',
      );
      // Die anderen beiden Bereiche sind weiter da.
      expect(
        [
          fake.weatherReads,
          fake.eventReads,
          fake.taskReads,
        ].where((n) => n > 0),
        hasLength(2),
      );
    });

    testWidgets('Bereich ${section.name} an: wird gelesen und gezeigt', (
      tester,
    ) async {
      final (_, fake) = await pumpStation(tester);
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(read(fake), 1);
    });
  }

  testWidgets('Platzhalter lassen sich ausblenden', (tester) async {
    await pumpStation(
      tester,
      prefs: const StationPrefs(
        hidden: {StationSection.playback, StationSection.tiles},
      ),
    );
    expect(find.byKey(const ValueKey('stationPlaybackSlot')), findsNothing);
    expect(find.byKey(const ValueKey('stationTilesSlot')), findsNothing);
  });

  testWidgets('Ruhezeit: nur Uhr und Datum, keine Titel', (tester) async {
    final (_, fake) = await pumpStation(
      tester,
      now: DateTime(2026, 10, 20, 23, 15),
    );
    expect(find.text('23:15'), findsOneWidget);
    expect(find.textContaining('Zahnarzt'), findsNothing);
    expect(find.byKey(const ValueKey('stationTasks')), findsNothing);
    expect(find.byKey(const ValueKey('stationEnd')), findsOneWidget);
    expect(fake.eventReads + fake.taskReads + fake.weatherReads, 0);
  });

  testWidgets('Berührung weckt die Station', (tester) async {
    final (host, _) = await pumpStation(
      tester,
      prefs: const StationPrefs(screenMode: StationScreenMode.touchOnly),
    );
    expect(host.last!.keepOn, isFalse);
    await tester.tapAt(const Offset(100, 300));
    await tester.pump();
    expect(host.last!.keepOn, isTrue);
    // Timer des Wach-Fensters ablaufen lassen.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('Beenden ohne Entsperren beendet nicht, mit Entsperren schon', (
    tester,
  ) async {
    final (host, _) = await pumpStation(tester);
    host.unlockAnswers = [false, true];
    await tester.tap(find.byKey(const ValueKey('stationEnd')));
    await tester.pump();
    expect(host.unlockRequests, 1);
    expect(host.finishes, 0);
    expect(find.text('12:34'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('stationEnd')));
    await tester.pump();
    expect(host.unlockRequests, 2);
    expect(host.finishes, 1);
  });

  group('Goldens', () {
    testWidgets('Ruhezustand hell', tags: ['golden'], (tester) async {
      await pumpStation(tester);
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/station_hell.png'),
      );
    });

    testWidgets('Ruhezustand dunkel (dunkler Raum)', tags: ['golden'], (
      tester,
    ) async {
      final (host, _) = await pumpStation(tester);
      host.dark.add(true);
      await tester.pump();
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/station_dunkel.png'),
      );
    });

    testWidgets('Ruhezeit', tags: ['golden'], (tester) async {
      await pumpStation(tester, now: DateTime(2026, 10, 20, 23, 15));
      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/station_ruhezeit.png'),
      );
    });
  });
}
