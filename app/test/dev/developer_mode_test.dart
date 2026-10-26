// WP148: Entwicklermodus – Schalter (10× „System“), Speicherung, Hinweis und
// die nur dort sichtbare Option „Bonus Hinweisbegriffe“.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/developer_mode.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/settings/app_language_screen.dart';
import 'package:wendelin/ui/settings/barge_debug_sheet.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin/ui/settings/voice_screen.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin_storage/fakes.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../settings/other_screens_test.dart' show pumpPage;
import '../support/test_env.dart';
import '../ui/helpers.dart';

Future<void> _tapSystem(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text('System'));
    await tester.pump();
  }
  await settle(tester);
}

void main() {
  const hint = 'Entwicklermodus an – erweitertes Logging';

  testWidgets('10× System schaltet ein, 10× wieder aus (Hinweis zählt ab 7.)', (
    tester,
  ) async {
    final env = TestEnv();
    final c = await pumpPage(tester, env, const AppLanguageScreen());
    await _tapSystem(tester, 6);
    expect(find.textContaining('Noch'), findsNothing);
    expect(c.read(developerModeProvider), isFalse);
    await _tapSystem(tester, 1);
    expect(
      find.text('Noch 3× tippen, um den Entwicklermodus einzuschalten'),
      findsOneWidget,
    );
    await _tapSystem(tester, 2);
    expect(c.read(developerModeProvider), isFalse);
    expect(devLogEnabled, isFalse);
    await _tapSystem(tester, 1);
    expect(c.read(developerModeProvider), isTrue);
    expect(devLogEnabled, isTrue);
    expect(find.text('Entwicklermodus an'), findsOneWidget);
    expect(
      await c.read(storageProvider).settings.get(AppSettings.developerMode),
      isTrue,
    );

    await _tapSystem(tester, 7);
    expect(
      find.text('Noch 3× tippen, um den Entwicklermodus auszuschalten'),
      findsOneWidget,
    );
    await _tapSystem(tester, 3);
    expect(c.read(developerModeProvider), isFalse);
    expect(devLogEnabled, isFalse);
    expect(find.text('Entwicklermodus aus'), findsOneWidget);
    expect(
      await c.read(storageProvider).settings.get(AppSettings.developerMode),
      isFalse,
    );
  });

  testWidgets('Tippen auf eine andere Sprache setzt den Zähler zurück', (
    tester,
  ) async {
    final c = await pumpPage(tester, TestEnv(), const AppLanguageScreen());
    await _tapSystem(tester, 9);
    await tester.tap(find.text('Deutsch'));
    await settle(tester);
    expect(c.read(uiLanguageProvider), 'de');
    await _tapSystem(tester, 1);
    expect(c.read(developerModeProvider), isFalse);
    expect(c.read(uiLanguageProvider), 'system');
  });

  testWidgets('erneutes „System“ lässt die Sprache unverändert', (
    tester,
  ) async {
    final c = await pumpPage(tester, TestEnv(), const AppLanguageScreen());
    await _tapSystem(tester, 4);
    expect(c.read(uiLanguageProvider), 'system');
    expect(find.text('App-Sprache'), findsWidgets);
  });

  testWidgets('Flag überlebt den Neustart', (tester) async {
    final first = TestEnv();
    final c = await pumpPage(tester, first, const AppLanguageScreen());
    await _tapSystem(tester, 10);
    expect(c.read(developerModeProvider), isTrue);

    // Neustart: StartupSettings.load liest, was gespeichert wurde.
    final startup = await StartupSettings.load(
      first.storage.settings,
      const [],
    );
    expect(startup.developerMode, isTrue);
    devLogEnabled = false;
    await tester.pumpWidget(const SizedBox()); // app closed
    final second = TestEnv(
      startup: StartupSettings(developerMode: startup.developerMode),
    );
    final c2 = await pumpPage(tester, second, const SettingsScreen());
    expect(c2.read(developerModeProvider), isTrue);
    expect(devLogEnabled, isTrue);
    expect(find.text(hint), findsOneWidget);
  });

  testWidgets('Hinweis in den Einstellungen nur im Entwicklermodus', (
    tester,
  ) async {
    await pumpPage(tester, TestEnv(), const SettingsScreen());
    expect(find.text(hint), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpPage(
      tester,
      TestEnv(startup: const StartupSettings(developerMode: true)),
      const SettingsScreen(),
    );
    expect(find.text(hint), findsOneWidget);
  });

  testWidgets('Bonus Hinweisbegriffe nur im Entwicklermodus, Wert bleibt', (
    tester,
  ) async {
    final storage = openInMemoryStorage();
    await storage.settings.set(AppSettings.hotwordsBonus, '1.5');
    final env = TestEnv(storage: storage);
    setView(tester, const Size(390, 5000));
    await tester.pumpWidget(env.app(home: const VoiceScreen()));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Erweitert'), 300);
    await tester.tap(find.text('Erweitert'));
    await settle(tester);
    expect(find.byType(BargeDebugSheet), findsOneWidget);
    expect(find.text('Bonus Hinweisbegriffe'), findsNothing);
    // Der Wert wirkt trotz verborgener Option.
    final c = ProviderScope.containerOf(
      tester.element(find.byType(BargeDebugSheet)),
    );
    expect(await c.read(hotwordsBonusProvider.future), 1.5);

    await c.read(developerModeProvider.notifier).set(enabled: true);
    await settle(tester);
    expect(find.text('Bonus Hinweisbegriffe'), findsOneWidget);
    await c.read(developerModeProvider.notifier).set(enabled: false);
    await settle(tester);
    expect(find.text('Bonus Hinweisbegriffe'), findsNothing);
    expect(await c.read(hotwordsBonusProvider.future), 1.5);
  });
}
