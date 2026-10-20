import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../di/provider_setup_test.dart' show RecordingFactory;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

TestEnv firstStart({RecordingFactory? factory}) => TestEnv(
  startup: const StartupSettings(onboardingDone: false),
  storedProfiles: true,
  llmFactory: (factory ?? RecordingFactory()).call,
);

/// Tall enough for the integrations step (more tiles than fit in 1400).
const onboardingTallView = Size(390, 1700);

Future<ProviderContainer> pumpApp(WidgetTester tester, TestEnv env) async {
  setView(tester, onboardingTallView);
  await tester.pumpWidget(env.app());
  await settle(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(OnboardingScreen)),
  );
}

void main() {
  testWidgets(
    'Schritt 0: App-Sprache wählbar, wirkt sofort, Sprechsprache bleibt',
    (tester) async {
      final env = firstStart();
      final c = await pumpApp(tester, env);
      expect(find.text('App-Sprache der Oberfläche'), findsOneWidget);
      await tester.tap(find.text('English').last);
      await settle(tester);
      expect(c.read(uiLanguageProvider), 'en');
      expect(c.read(languageProvider), isNot('en'));
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(await env.storage.settings.get(AppSettings.uiLanguage), 'en');
    },
  );

  testWidgets('erster Start: Sprache, später Provider, Integrationen, Fertig', (
    tester,
  ) async {
    final env = firstStart();
    final c = await pumpApp(tester, env);
    expect(find.byType(MainScreen), findsNothing);
    expect(find.text('Willkommen'), findsOneWidget);
    expect(find.textContaining('Whisper'), findsNothing);

    await tester.tap(find.text('Français').first);
    await settle(tester);
    expect(c.read(languageProvider), 'fr');
    expect(await env.storage.settings.get(AppSettings.language), 'fr');
    await tester.tap(find.text('Weiter'));
    await settle(tester);

    expect(find.text('Sprachmodell'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await settle(tester);

    expect(find.text('Spracherkennung laden'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await settle(tester);

    // Gesprächsmodus (M4, Entscheidung 2): eigener Schritt, Antwort wird
    // gespeichert, die Nachfrage im Hauptbildschirm kommt dann nie.
    expect(find.text('Gespräch'), findsOneWidget);
    expect(find.textContaining('Einstellungen → Sprache'), findsOneWidget);
    await tester.tap(find.text('Ja, weiter zuhören'));
    await settle(tester);
    final voice = await c.read(voiceSettingsProvider.future);
    expect(voice.conversationMode, isTrue);
    expect(voice.conversationAsked, isTrue);

    expect(find.text('Was darf Wendelin?'), findsOneWidget);
    await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
    await tester.pumpAndSettle();
    expect(env.permissionRequests, 0);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(IntegrationTile, 'Zwischenablage'),
        matching: find.byType(WSwitch),
      ),
    );
    await settle(tester);
    expect(c.read(enabledIntegrationsProvider), contains('clipboard'));

    // Letzter Schritt (WP50 b): Aktivierungswort, überspringbar.
    await tester.scrollUntilVisible(find.text('Weiter'), 200);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(find.text('Aktivierungswort'), findsOneWidget);
    await tester.tap(find.text('Überspringen'));
    await settle(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(await env.storage.settings.get(AppSettings.onboardingDone), isTrue);
  });

  testWidgets('Provider im Onboarding einrichten', (tester) async {
    final f = RecordingFactory(
      models: const [ModelInfo(id: 'claude-haiku-5-5')],
    );
    final env = firstStart(factory: f);
    await pumpApp(tester, env);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    await tester.tap(find.text('Provider einrichten'));
    await settle(tester);
    expect(find.byType(ProviderSetupScreen), findsOneWidget);
    await tester.tap(find.text('Claude'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('apiKey')),
      'testschluessel-x',
    );
    await tester.tap(find.text('Verbindung testen'));
    await settle(tester);
    await tester.tap(find.text('Modell prüfen'));
    await settle(tester);
    await tester.tap(find.text('Speichern'));
    await settle(tester);
    expect(find.text('Spracherkennung laden'), findsOneWidget);
    expect(await env.storage.providerProfiles.defaultProfile(), isNotNull);
  });

  testWidgets('Demo ohne Provider beendet das Onboarding (Debug)', (
    tester,
  ) async {
    final env = firstStart();
    final c = await pumpApp(tester, env);
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    await tester.tap(find.text('Demo ohne Provider'));
    await settle(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(c.read(demoModeProvider), isTrue);
    expect(c.read(onboardingDoneProvider), isTrue);
  });

  testWidgets(
    'Demo ohne Provider mit echten Demo-Ports (Vault): kein Provider-Update '
    'während des Aufbaus (Regression WP11)',
    (tester) async {
      final env = TestEnv(
        startup: const StartupSettings(onboardingDone: false),
        storedProfiles: true,
        llmFactory: RecordingFactory().call,
        realDemoPorts: true,
      );
      final c = await pumpApp(tester, env);
      await tester.tap(find.text('Weiter'));
      await settle(tester);
      await tester.tap(find.text('Demo ohne Provider'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(MainScreen), findsOneWidget);
      expect(c.read(platformPortsProvider).obsidian?.hasVault(), isTrue);
    },
  );

  testWidgets('nach dem Onboarding startet die App im Hauptbildschirm', (
    tester,
  ) async {
    setView(tester, screenSize);
    await tester.pumpWidget(TestEnv().app());
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(MainScreen), findsOneWidget);
  });

  group('B4: Zurück im Onboarding', () {
    /// Records `SystemNavigator.pop` (Android closes the app).
    List<String> recordSystemPop(WidgetTester tester) {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await settle(tester);
    }

    testWidgets('Geste: ab Schritt 2 einen Schritt zurück, in Schritt 1 zu', (
      tester,
    ) async {
      await pumpApp(tester, firstStart());
      final pops = recordSystemPop(tester);
      expect(find.byTooltip('Zurück'), findsNothing, reason: 'Schritt 1');
      await tester.tap(find.text('Weiter'));
      await settle(tester);
      await tester.tap(find.text('Später'));
      await settle(tester);
      expect(find.text('Spracherkennung laden'), findsOneWidget);

      await back(tester);
      expect(find.text('Sprachmodell'), findsOneWidget);
      expect(pops.where((m) => m == 'SystemNavigator.pop'), isEmpty);
      await back(tester);
      expect(find.text('Willkommen'), findsOneWidget);
      expect(pops.where((m) => m == 'SystemNavigator.pop'), isEmpty);

      await back(tester);
      expect(
        pops.where((m) => m == 'SystemNavigator.pop'),
        hasLength(1),
        reason: 'Schritt 1: Android schließt die App',
      );
    });

    testWidgets('Pfeil ab Schritt 2, auch im letzten Schritt', (tester) async {
      await pumpApp(tester, firstStart());
      await tester.tap(find.text('Weiter'));
      await settle(tester);
      expect(find.byTooltip('Zurück'), findsOneWidget);
      await tester.tap(find.text('Später'));
      await settle(tester);
      await tester.tap(find.text('Später'));
      await settle(tester);
      await tester.tap(find.text('Nein, nur nach Tippen'));
      await settle(tester);
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await settle(tester);
      expect(find.text('Gespräch'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await settle(tester);
      expect(find.text('Spracherkennung laden'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await settle(tester);
      expect(find.text('Sprachmodell'), findsOneWidget);
      final size = tester.getSize(find.byTooltip('Zurück'));
      expect(size.width, greaterThanOrEqualTo(WSize.touchMin));
      expect(size.height, greaterThanOrEqualTo(WSize.touchMin));
    });

    testWidgets('Zurück aus der Provider-Einrichtung bleibt im Schritt 2', (
      tester,
    ) async {
      await pumpApp(tester, firstStart());
      await tester.tap(find.text('Weiter'));
      await settle(tester);
      await tester.tap(find.text('Provider einrichten'));
      await settle(tester);
      expect(find.byType(ProviderSetupScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(ProviderSetupScreen), findsNothing);
      expect(find.text('Sprachmodell'), findsOneWidget);
    });
  });

  testWidgets('Provider-Schritt: Inhalt vertikal mittig, solange er passt', (
    tester,
  ) async {
    await pumpApp(tester, firstStart());
    setView(tester, screenSize);
    await tester.pump();
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    final intro = find.textContaining('Wendelin braucht');
    // Last element in debug builds: „Demo ohne Provider“.
    final last = find.widgetWithText(OutlinedButton, 'Demo ohne Provider');
    final area = tester.getRect(
      find.ancestor(of: intro, matching: find.byType(Column)).first,
    );
    final top = tester.getTopLeft(intro).dy - area.top;
    final below = area.bottom - tester.getBottomLeft(last).dy;
    // Equal space above and below the content, a lot of it on a phone.
    expect(top, closeTo(below, 1));
    expect(top, greaterThan(100));
    expect(
      area.bottom,
      closeTo(
        tester.getSize(find.byType(OnboardingScreen)).height - WSpace.xl24,
        1,
      ),
    );
  });
}
