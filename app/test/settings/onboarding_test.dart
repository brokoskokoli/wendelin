import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/setup_wizard.dart';
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

TestEnv firstStart({
  RecordingFactory? factory,
  String? page,
  bool withSpeech = false,
  int? memory,
}) {
  final env = TestEnv(
    extraOverrides: [
      if (memory != null)
        deviceMemoryProvider.overrideWith((ref) async => memory),
    ],
    startup: StartupSettings(setupWizardDone: false, setupWizardPage: page),
    storedProfiles: true,
    llmFactory: (factory ?? RecordingFactory()).call,
  );
  if (withSpeech) {
    env.speechModels.installed.addAll(['whisper-small', 'silero-vad']);
  }
  return env;
}

Future<void> seedProvider(TestEnv env) =>
    env.storage.providerProfiles.save(testProfile());

ProviderProfile testProfile() => ProviderProfile(
  id: 'p1',
  name: 'Mein Claude',
  type: ProviderType.anthropic,
  defaultModel: 'claude-haiku-5-5',
  privacy: PrivacyLevel.standard,
  authMethod: const NoAuth(),
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

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
  await settle(tester);
}

void main() {
  testWidgets('erster Start: alle sieben Seiten bis zum Hauptbildschirm', (
    tester,
  ) async {
    final env = firstStart(withSpeech: true);
    await seedProvider(env);
    final c = await pumpApp(tester, env);
    expect(find.byType(MainScreen), findsNothing);
    expect(find.text('Willkommen'), findsOneWidget);

    await tapText(tester, 'Los geht’s');

    expect(find.text('Anbieter eingerichtet: Mein Claude'), findsOneWidget);
    await tapText(tester, 'Weiter');

    expect(find.text('Spracherkennung'), findsOneWidget);
    expect(find.text('Bereit'), findsOneWidget);
    await tapText(tester, 'Weiter');

    expect(find.text('Aktivierungswort'), findsOneWidget);
    expect(find.text('Aktivierungswort nicht eingerichtet'), findsOneWidget);
    await tapText(tester, 'Ohne fortfahren');

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
    await tapText(tester, 'Weiter');

    expect(find.text('Personalisierung'), findsOneWidget);
    await tapText(tester, 'Ohne fortfahren');

    expect(find.text('Fertig'), findsOneWidget);
    expect(find.byType(MainScreen), findsNothing);
    await tapText(tester, 'Los geht’s');
    expect(find.byType(MainScreen), findsOneWidget);
    expect(await env.storage.settings.get(AppSettings.setupWizardDone), isTrue);
    expect(c.read(setupWizardDoneProvider), isTrue);
  });

  testWidgets(
    'Provider im Assistenten einrichten: Seite zeigt es, dann Weiter',
    (tester) async {
      final f = RecordingFactory(
        models: const [ModelInfo(id: 'claude-haiku-5-5')],
      );
      final env = firstStart(factory: f);
      await pumpApp(tester, env);
      await tester.tap(find.text('Los geht’s'));
      await settle(tester);
      expect(find.text('Noch kein Anbieter eingerichtet'), findsOneWidget);
      await tester.tap(find.text('Anbieter eintragen'));
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
      // Back on the provider page, which now says so; no automatic jump.
      expect(find.byType(ProviderSetupScreen), findsNothing);
      expect(find.text('Anbieter eingerichtet: Claude'), findsOneWidget);
      expect(await env.storage.providerProfiles.defaultProfile(), isNotNull);
      await tapText(tester, 'Weiter');
      expect(find.text('Spracherkennung'), findsOneWidget);
    },
  );

  testWidgets('Demo ohne Provider überspringt den Assistenten (Debug)', (
    tester,
  ) async {
    final env = firstStart();
    final c = await pumpApp(tester, env);
    await tester.tap(find.text('Los geht’s'));
    await settle(tester);
    await tester.tap(find.text('Demo ohne Provider'));
    await settle(tester);
    expect(find.byType(MainScreen), findsOneWidget);
    expect(c.read(demoModeProvider), isTrue);
  });

  testWidgets(
    'Demo ohne Provider mit echten Demo-Ports (Vault): kein Provider-Update '
    'während des Aufbaus (Regression WP11)',
    (tester) async {
      final env = TestEnv(
        startup: const StartupSettings(setupWizardDone: false),
        storedProfiles: true,
        llmFactory: RecordingFactory().call,
        realDemoPorts: true,
      );
      final c = await pumpApp(tester, env);
      await tester.tap(find.text('Los geht’s'));
      await settle(tester);
      await tester.tap(find.text('Demo ohne Provider'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(MainScreen), findsOneWidget);
      expect(c.read(platformPortsProvider).obsidian?.hasVault(), isTrue);
    },
  );

  testWidgets('nach dem Assistenten startet die App im Hauptbildschirm', (
    tester,
  ) async {
    setView(tester, screenSize);
    await tester.pumpWidget(TestEnv().app());
    await settle(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(MainScreen), findsOneWidget);
  });

  group('Zurück im Assistenten (Seiten)', () {
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

    testWidgets('Geste: ab Seite 2 eine Seite zurück, auf Seite 1 zu', (
      tester,
    ) async {
      final env = firstStart(withSpeech: true);
      await seedProvider(env);
      await pumpApp(tester, env);
      final pops = recordSystemPop(tester);
      expect(find.byTooltip('Zurück'), findsNothing, reason: 'Seite 1');
      await tapText(tester, 'Los geht’s');
      await tapText(tester, 'Weiter');
      expect(find.text('Spracherkennung'), findsOneWidget);

      await back(tester);
      expect(find.text('KI-Anbieter'), findsOneWidget);
      expect(pops.where((m) => m == 'SystemNavigator.pop'), isEmpty);
      await back(tester);
      expect(find.text('Willkommen'), findsOneWidget);
      expect(pops.where((m) => m == 'SystemNavigator.pop'), isEmpty);

      await back(tester);
      expect(
        pops.where((m) => m == 'SystemNavigator.pop'),
        hasLength(1),
        reason: 'Seite 1: Android schließt die App',
      );
    });

    testWidgets('Pfeil ab Seite 2, auch auf der letzten Seite', (tester) async {
      final env = firstStart(page: 'done', withSpeech: true);
      await seedProvider(env);
      await pumpApp(tester, env);
      expect(find.text('Fertig'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await settle(tester);
      expect(find.text('Personalisierung'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await settle(tester);
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
      final size = tester.getSize(find.byTooltip('Zurück'));
      expect(size.width, greaterThanOrEqualTo(WSize.touchMin));
      expect(size.height, greaterThanOrEqualTo(WSize.touchMin));
    });

    testWidgets('Zurück aus der Provider-Einrichtung bleibt auf der Seite', (
      tester,
    ) async {
      await pumpApp(tester, firstStart());
      await tester.tap(find.text('Los geht’s'));
      await settle(tester);
      await tester.tap(find.text('Anbieter eintragen'));
      await settle(tester);
      expect(find.byType(ProviderSetupScreen), findsOneWidget);
      await back(tester);
      expect(find.byType(ProviderSetupScreen), findsNothing);
      expect(find.text('KI-Anbieter'), findsOneWidget);
    });
  });

  testWidgets('Provider-Seite: Inhalt vertikal mittig, solange er passt', (
    tester,
  ) async {
    await pumpApp(tester, firstStart());
    setView(tester, screenSize);
    await tester.pump();
    await tester.tap(find.text('Los geht’s'));
    await settle(tester);
    final intro = find.textContaining('Wendelin braucht');
    // Last element in debug builds: „Demo ohne Provider“.
    final last = find.widgetWithText(OutlinedButton, 'Demo ohne Provider');
    final area = tester.getRect(
      find.ancestor(of: intro, matching: find.byType(Column)).first,
    );
    final box = find.ancestor(of: intro, matching: find.byType(InfoBox));
    final top = tester.getTopLeft(box).dy - area.top;
    final below = area.bottom - tester.getBottomLeft(last).dy;
    // Equal space above and below the content.
    expect(top, closeTo(below, 1));
    expect(top, greaterThan(40));
    expect(
      area.bottom,
      closeTo(
        tester.getSize(find.byType(OnboardingScreen)).height - WSpace.xl24,
        1,
      ),
    );
  });
}
