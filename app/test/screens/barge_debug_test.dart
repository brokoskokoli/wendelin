// WP72/WP80: Entwickler-Varianten („Erweitert“) für Barge-in – Markierung „Standard“, Zurücksetzen
// und Hinweis in der Gesprächs-Sektion.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/core_providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/voice/record_audio_input.dart';
import 'package:wendelin/ui/settings/barge_debug_sheet.dart';
import 'package:wendelin/ui/settings/voice_screen.dart';

import '../settings/integrations_screen_test.dart' show settle;
import '../support/test_env.dart';
import '../ui/helpers.dart';

void main() {
  const hint = 'Eigene Einstellung für das Unterbrechen aktiv';

  testWidgets('Standard markiert, Hinweis erst bei Abweichung, Zurücksetzen', (
    tester,
  ) async {
    final env = TestEnv();
    setView(tester, const Size(390, 5000));
    await tester.pumpWidget(env.app(home: const VoiceScreen()));
    await settle(tester);
    expect(find.textContaining(hint), findsNothing);

    await tester.scrollUntilVisible(find.text('Erweitert'), 300);
    await tester.tap(find.text('Erweitert'));
    await settle(tester);
    // WP80: every option is explained.
    expect(find.textContaining('rechnet die eigene Ausgabe'), findsOneWidget);
    // WP118: the title of the new switch mentions it as well.
    expect(find.textContaining('Echo-Unterdrückung'), findsNWidgets(2));
    expect(find.textContaining('mehr Fehlalarme'), findsOneWidget);
    expect(find.text('Kommunikation + AEC (Standard)'), findsOneWidget);
    expect(find.text('0,05 (Standard)'), findsOneWidget);

    await tester.tap(find.text('Erkennung, ohne AEC'));
    await settle(tester);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(BargeDebugSheet)),
    );
    expect(
      await c.read(storageProvider).settings.get(AppSettings.bargeSource),
      SpeechCapture.recognition.name,
    );
    expect(await c.read(bargeVariantActiveProvider.future), isTrue);

    await tester.tap(find.text('Zurücksetzen'));
    await settle(tester);
    expect(
      await c.read(storageProvider).settings.get(AppSettings.bargeSource),
      SpeechCapture.communication.name,
    );
    expect(
      await c.read(storageProvider).settings.get(AppSettings.bargeMargin),
      bargeMarginChoices.first,
    );
    expect(await c.read(bargeVariantActiveProvider.future), isFalse);
  });

  testWidgets('Bonus Hinweisbegriffe: Standard 1,0, Wahl wird gespeichert', (
    tester,
  ) async {
    final env = TestEnv(startup: const StartupSettings(developerMode: true));
    setView(tester, const Size(390, 5000));
    await tester.pumpWidget(env.app(home: const VoiceScreen()));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Erweitert'), 300);
    await tester.tap(find.text('Erweitert'));
    await settle(tester);
    expect(find.text('Bonus Hinweisbegriffe'), findsOneWidget);
    expect(find.text('1,0 (Standard)'), findsOneWidget);
    await tester.ensureVisible(find.text('1,5'));
    await tester.tap(find.text('1,5'));
    await settle(tester);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(BargeDebugSheet)),
    );
    expect(
      await c.read(storageProvider).settings.get(AppSettings.hotwordsBonus),
      '1.5',
    );
    expect(await c.read(hotwordsBonusProvider.future), 1.5);
  });

  testWidgets('Hinweis in der Gesprächs-Sektion bei aktiver Variante', (
    tester,
  ) async {
    final env = TestEnv();
    await env.storage.settings.set(AppSettings.bargeMargin, '0.00');
    setView(tester, const Size(390, 5000));
    await tester.pumpWidget(env.app(home: const VoiceScreen()));
    await settle(tester);
    expect(find.textContaining(hint), findsOneWidget);
  });

  testWidgets('Schalter „Antwort als Gesprächston“: Standard aus, speichert', (
    tester,
  ) async {
    final env = TestEnv();
    setView(tester, const Size(390, 5000));
    await tester.pumpWidget(env.app(home: const VoiceScreen()));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Erweitert'), 300);
    await tester.tap(find.text('Erweitert'));
    await settle(tester);
    final tile = find.widgetWithText(
      SwitchListTile,
      'Antwort als Gesprächston (bessere Echo-Unterdrückung)',
    );
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(BargeDebugSheet)),
    );
    expect(
      await c
          .read(storageProvider)
          .settings
          .get(AppSettings.speechCommunication),
      isFalse,
    );

    await tester.tap(tile);
    await settle(tester);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    expect(
      await c
          .read(storageProvider)
          .settings
          .get(AppSettings.speechCommunication),
      isTrue,
    );
    // „Zurücksetzen“ betrifft nur das Unterbrechen.
    expect(find.textContaining('Nebenwirkungen'), findsOneWidget);
  });
}
