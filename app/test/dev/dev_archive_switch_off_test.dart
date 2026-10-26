// WP155: Ausschalten des Entwicklermodus löscht die kurzlebigen Aufnahmen
// sofort; das Weckwort-Archiv nur auf Wunsch (Rückfrage nur bei vollem
// Archiv). Dazu die Archiv-Zeile in den Einstellungen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/developer_mode.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/settings/app_language_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin/voice/dev_archive.dart';
import 'package:wendelin/voice/dev_audio.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../settings/other_screens_test.dart' show pumpPage;
import '../support/test_env.dart';

DevArchiveEntry entry(int second) => DevArchiveEntry(
  at: DateTime(2026, 10, 26, 12, 0, second),
  source: 'idle',
  outcome: 'accepted',
  meta: const {'score': 0.9},
  cand: DevClip(
    event: 'x',
    pcm: Int16List(1000),
    at: DateTime(2026, 10, 26),
    marksMs: const {},
  ),
);

void main() {
  late Directory root;
  late Directory audio;

  setUp(() {
    root = Directory.systemTemp.createTempSync('devoff');
    audio = Directory('${root.path}/dev-audio')..createSync();
    devLogSink = (_) {};
    devAudioDirectory = () async => audio;
    addTearDown(() {
      devLogEnabled = false;
      root.deleteSync(recursive: true);
    });
  });

  /// A short-lived recording and [n] archive cases.
  Future<void> seed({int n = 1}) async {
    devLogEnabled = true;
    File('${audio.path}/20261026-000000.000_barge-cand.wav')
        .writeAsBytesSync([1, 2, 3]);
    for (var i = 0; i < n; i++) {
      saveDevArchiveEntry(entry(i));
    }
    await devArchiveIdle;
  }

  List<String> recordings() => [
    for (final f in audio.listSync().whereType<File>()) f.path,
  ];
  bool archiveThere() =>
      Directory('${audio.path}/$devArchiveFolder').existsSync();

  group('DeveloperModePref.set', () {
    test('aus: kurzlebige Aufnahmen weg, Archiv bleibt', () async {
      await seed();
      final c = TestEnv().container();
      addTearDown(c.dispose);
      await c.read(developerModeProvider.notifier).set(enabled: false);
      expect(recordings(), isEmpty);
      expect(archiveThere(), isTrue);
      expect((await devArchiveStats()).cases, 1);
      expect(devLogEnabled, isFalse);
    });

    test('aus mit deleteArchive: auch das Archiv ist weg', () async {
      await seed();
      final c = TestEnv().container();
      addTearDown(c.dispose);
      await c
          .read(developerModeProvider.notifier)
          .set(enabled: false, deleteArchive: true);
      expect(recordings(), isEmpty);
      expect(archiveThere(), isFalse);
    });

    test('an löscht nichts', () async {
      await seed();
      final c = TestEnv().container();
      addTearDown(c.dispose);
      await c.read(developerModeProvider.notifier).set(enabled: true);
      expect(recordings(), hasLength(1));
      expect(archiveThere(), isTrue);
    });

    test(
      'ein wartender Eintrag landet nach dem Ausschalten nicht mehr',
      () async {
        await seed();
        final c = TestEnv().container();
        addTearDown(c.dispose);
        saveDevArchiveEntry(entry(30)); // waits in the queue
        await c.read(developerModeProvider.notifier).set(enabled: false);
        await devArchiveIdle;
        expect((await devArchiveStats()).cases, 1);
      },
    );
  });

  Future<void> tapSystem(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.text('System'));
      await tester.pump();
    }
  }

  TestEnv devEnv() =>
      TestEnv(startup: const StartupSettings(developerMode: true));

  group('Rückfrage in der Sprachseite', () {
    testWidgets('leeres Archiv: keine Frage, Modus aus', (tester) async {
      await tester.runAsync(() => seed(n: 0));
      final c = await pumpPage(tester, devEnv(), const AppLanguageScreen());
      await tapSystem(tester, 10);
      await settle(tester, until: () => recordings().isEmpty);
      expect(c.read(developerModeProvider), isFalse);
      expect(find.text('Weckwort-Archiv mitlöschen?'), findsNothing);
      expect(recordings(), isEmpty);
    });

    testWidgets('Behalten: Modus aus, Archiv bleibt', (tester) async {
      await tester.runAsync(() => seed(n: 2));
      final c = await pumpPage(tester, devEnv(), const AppLanguageScreen());
      await tapSystem(tester, 10);
      await settle(
        tester,
        until: () =>
            find.text('Weckwort-Archiv mitlöschen?').evaluate().isNotEmpty,
      );
      expect(find.textContaining('2 Einträge'), findsOneWidget);
      // Nothing is touched while the question is open.
      expect(c.read(developerModeProvider), isTrue);
      await tester.tap(find.text('Behalten'));
      await settle(tester, until: () => recordings().isEmpty);
      expect(c.read(developerModeProvider), isFalse);
      expect(archiveThere(), isTrue);
      expect(recordings(), isEmpty);
    });

    testWidgets('Mitlöschen: Archiv weg', (tester) async {
      await tester.runAsync(() => seed(n: 2));
      final c = await pumpPage(tester, devEnv(), const AppLanguageScreen());
      await tapSystem(tester, 10);
      await settle(
        tester,
        until: () =>
            find.text('Weckwort-Archiv mitlöschen?').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Mitlöschen'));
      await settle(tester, until: () => recordings().isEmpty);
      expect(c.read(developerModeProvider), isFalse);
      await settle(tester, until: () => !archiveThere());
      expect(archiveThere(), isFalse);
      expect(recordings(), isEmpty);
    });
  });

  group('Einstellungen', () {
    testWidgets('Archiv-Zeile: leer, mit Einträgen, Löschen mit Rückfrage', (
      tester,
    ) async {
      await tester.runAsync(() => seed(n: 0));
      await pumpPage(tester, devEnv(), const SettingsScreen());
      expect(find.text('Weckwort-Archiv'), findsOneWidget);
      expect(find.text('Noch keine Einträge'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await tester.runAsync(() => seed(n: 3));
      await pumpPage(tester, devEnv(), const SettingsScreen());
      await settle(
        tester,
        until: () => find.textContaining('3 Einträge').evaluate().isNotEmpty,
      );
      // Abbrechen löscht nichts.
      await tester.tap(find.widgetWithText(TextButton, 'Archiv löschen'));
      await settle(tester);
      expect(find.text('Archiv löschen?'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await settle(tester);
      expect(archiveThere(), isTrue);
      // Bestätigen löscht.
      await tester.tap(find.widgetWithText(TextButton, 'Archiv löschen'));
      await settle(tester);
      await tester.tap(find.text('Archiv löschen').last);
      await settle(tester, until: () => !archiveThere());
      await settle(
        tester,
        until: () => find.text('Noch keine Einträge').evaluate().isNotEmpty,
      );
      expect(find.text('Noch keine Einträge'), findsOneWidget);
    });

    testWidgets('ohne Entwicklermodus keine Archiv-Zeile', (tester) async {
      await pumpPage(tester, TestEnv(), const SettingsScreen());
      expect(find.text('Weckwort-Archiv'), findsNothing);
    });
  });
}
