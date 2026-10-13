import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
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

Future<ProviderContainer> pumpApp(WidgetTester tester, TestEnv env) async {
  setView(tester, const Size(390, 1400));
  await tester.pumpWidget(env.app());
  await settle(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(OnboardingScreen)),
  );
}

void main() {
  testWidgets('erster Start: Sprache, später Provider, Integrationen, Fertig', (
    tester,
  ) async {
    final env = firstStart();
    final c = await pumpApp(tester, env);
    expect(find.byType(MainScreen), findsNothing);
    expect(find.text('Willkommen'), findsOneWidget);
    expect(find.textContaining('Whisper'), findsNothing, reason: 'erst M2');

    await tester.tap(find.text('Français'));
    await settle(tester);
    expect(c.read(languageProvider), 'fr');
    expect(await env.storage.settings.get(AppSettings.language), 'fr');
    await tester.tap(find.text('Weiter'));
    await settle(tester);

    expect(find.text('Sprachmodell'), findsOneWidget);
    await tester.tap(find.text('Später'));
    await settle(tester);

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

    await tester.tap(find.text('Fertig'));
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
    expect(find.text('Was darf Wendelin?'), findsOneWidget);
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

  testWidgets('nach dem Onboarding startet die App im Hauptbildschirm', (
    tester,
  ) async {
    setView(tester, screenSize);
    await tester.pumpWidget(TestEnv().app());
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(MainScreen), findsOneWidget);
  });
}
