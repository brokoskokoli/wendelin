import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/di/setup_status.dart';
import 'package:wendelin/di/setup_wizard.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/speaker/speaker_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_enroll_screen.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'onboarding_test.dart' show testProfile;

/// The key of the former onboarding, written by older app versions.
final _legacyOnboardingDone = SettingKey.boolean('onboarding.done');

/// An env on a prepared storage; the startup settings are read from it like
/// in the real app (`StartupSettings.load`).
Future<TestEnv> envOn(
  WendelinStorage storage, {
  bool provider = true,
  bool speech = true,
}) async {
  if (provider) await storage.providerProfiles.save(testProfile());
  final startup = await StartupSettings.load(storage.settings, const []);
  final env = TestEnv(storage: storage, startup: startup, storedProfiles: true);
  if (speech) {
    env.speechModels.installed.addAll(['whisper-small', 'silero-vad']);
  }
  return env;
}

Future<ProviderContainer> pump(WidgetTester tester, TestEnv env) async {
  setView(tester, const Size(390, 1700));
  await tester.pumpWidget(env.app());
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
  await settle(tester);
}

NavigatorState navigator(WidgetTester tester) =>
    Navigator.of(tester.element(find.byType(Scaffold).first));

Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

void main() {
  group('Gespeicherter Zustand', () {
    test('Update-Fall: onboarding.done=true, neuer Schlüssel fehlt', () async {
      final storage = openInMemoryStorage();
      await storage.settings.set(_legacyOnboardingDone, true);
      final startup = await StartupSettings.load(storage.settings, const []);
      expect(startup.setupWizardDone, isFalse);
      expect(startup.setupWizardPage, isNull);
    });

    test('frische Installation: nicht fertig; gespeichert: fertig', () async {
      final storage = openInMemoryStorage();
      final fresh = await StartupSettings.load(storage.settings, const []);
      expect(fresh.setupWizardDone, isFalse);
      await storage.settings.set(AppSettings.setupWizardDone, true);
      await storage.settings.set(AppSettings.setupWizardPage, 'wakeWord');
      final s = await StartupSettings.load(storage.settings, const []);
      expect(s.setupWizardDone, isTrue);
      expect(s.setupWizardPage, 'wakeWord');
    });
  });

  group('Assistent beim Start', () {
    testWidgets('Update-Fall: Bestandsinstallation sieht ihn, Anbieter und '
        'Sprache sind schon erfüllt', (tester) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(_legacyOnboardingDone, true);
      final env = await envOn(storage);
      await pump(tester, env);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      await tapText(tester, 'Los geht’s');
      expect(find.textContaining('Anbieter eingerichtet:'), findsOneWidget);
      await tapText(tester, 'Weiter');
      expect(find.text('Bereit'), findsOneWidget);
    });

    testWidgets('abgeschlossen: Hauptbildschirm, kein Assistent', (
      tester,
    ) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardDone, true);
      await pump(tester, await envOn(storage));
      expect(find.byType(MainScreen), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsNothing);
    });

    testWidgets('Fortsetzen an der gespeicherten Seite', (tester) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardPage, 'integrations');
      await pump(tester, await envOn(storage));
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
    });

    testWidgets('Seitenwechsel wird gespeichert', (tester) async {
      final storage = openInMemoryStorage();
      final env = await envOn(storage);
      await pump(tester, env);
      await tapText(tester, 'Los geht’s');
      expect(
        await storage.settings.get(AppSettings.setupWizardPage),
        'provider',
      );
      await tapText(tester, 'Weiter');
      expect(await storage.settings.get(AppSettings.setupWizardPage), 'speech');
    });

    testWidgets('gespeicherte Seite hinter unerfülltem Pflichtschritt: '
        'zeigt den Pflichtschritt', (tester) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(
        AppSettings.setupWizardPage,
        'personalization',
      );
      final env = await envOn(storage, provider: false);
      await pump(tester, env);
      expect(find.text('Noch kein Anbieter eingerichtet'), findsOneWidget);
    });

    testWidgets('unbekannte gespeicherte Seite: Anfang', (tester) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardPage, 'gibtsNicht');
      await pump(tester, await envOn(storage));
      expect(find.text('Willkommen'), findsOneWidget);
    });

    testWidgets('Abschluss erst mit erfüllten Pflichtseiten, fail-closed', (
      tester,
    ) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardPage, 'done');
      final env = await envOn(storage, speech: false);
      final c = await pump(tester, env);
      // „done“ is shown only behind met required pages: speech is not met.
      expect(find.text('Spracherkennung'), findsOneWidget);
      expect(await c.read(setupWizardPageProvider.notifier).finish(), isFalse);
      expect(c.read(setupWizardDoneProvider), isFalse);
      expect(
        await storage.settings.get(AppSettings.setupWizardDone),
        isNot(true),
      );
    });
  });

  group('Stand aus dem Live-Zustand', () {
    testWidgets('Anbieter und Sprache werden abgeleitet, nichts gespeichert', (
      tester,
    ) async {
      final storage = openInMemoryStorage();
      final env = await envOn(storage, provider: false, speech: false);
      final c = await pump(tester, env);
      SetupFacts facts() => c.read(setupFactsProvider);
      expect(facts().providerConfigured, isFalse);
      expect(facts().speechReady, isFalse);

      await storage.providerProfiles.save(testProfile());
      c.invalidate(profilesProvider);
      env.speechModels.installed.add('whisper-small');
      await c.read(modelStatesProvider.notifier).refresh();
      await settle(tester);
      expect(facts().providerConfigured, isTrue);
      expect(facts().speechReady, isFalse, reason: 'VAD fehlt noch');

      env.speechModels.installed.add('silero-vad');
      await c.read(modelStatesProvider.notifier).refresh();
      await settle(tester);
      expect(facts().speechReady, isTrue);

      // Removed again: no longer ticked (nothing was stored).
      env.speechModels.installed.remove('silero-vad');
      await c.read(modelStatesProvider.notifier).refresh();
      await settle(tester);
      expect(facts().speechReady, isFalse);
    });

    testWidgets('Fehler beim Lesen der Anbieter: unbekannt, Weiter gesperrt', (
      tester,
    ) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardPage, 'provider');
      final env = await envOn(storage);
      final c = await pump(tester, env);
      expect(c.read(setupFactsProvider).providerConfigured, isTrue);
      // The database becomes unreadable: the state is unknown, not met.
      await tester.runAsync(storage.close);
      c.invalidate(profilesProvider);
      await settle(tester);
      expect(c.read(profilesProvider).hasError, isTrue);
      expect(c.read(setupFactsProvider).providerConfigured, isNull);
      expect(find.text('Noch kein Anbieter eingerichtet'), findsOneWidget);
      final next = find.widgetWithText(OutlinedButton, 'Weiter');
      expect(tester.widget<OutlinedButton>(next).onPressed, isNull);
      expect(await c.read(setupWizardPageProvider.notifier).advance(), isFalse);
    });
  });

  group('Zurück aus Einstellungsmenüs des Assistenten', () {
    Future<(TestEnv, ProviderContainer)> onWakePage(WidgetTester tester) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardPage, 'wakeWord');
      final env = await envOn(storage);
      final c = await pump(tester, env);
      expect(find.text('Aktivierungswort nicht eingerichtet'), findsOneWidget);
      return (env, c);
    }

    testWidgets('AppBar-Pfeil führt auf die Assistentenseite', (tester) async {
      await onWakePage(tester);
      await tapText(tester, 'Einlernen und einschalten');
      expect(find.byType(OnboardingScreen), findsNothing);
      await tester.tap(find.byTooltip('Zurück').first);
      await settle(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Aktivierungswort nicht eingerichtet'), findsOneWidget);
    });

    testWidgets('System-Zurück führt auf die Assistentenseite', (tester) async {
      await onWakePage(tester);
      await tapText(tester, 'Einlernen und einschalten');
      await systemBack(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(find.text('Aktivierungswort nicht eingerichtet'), findsOneWidget);
    });

    testWidgets('auch aus Unterseiten: ein Zurück genügt', (tester) async {
      await onWakePage(tester);
      await tapText(tester, 'Einlernen und einschalten');
      unawaited(navigator(tester).pushNamed<void>(AppRoutes.speaker));
      await settle(tester);
      await tester.tap(find.byTooltip('Zurück').first);
      await settle(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(navigator(tester).canPop(), isFalse);

      await tapText(tester, 'Einlernen und einschalten');
      unawaited(navigator(tester).pushNamed<void>(AppRoutes.speaker));
      await settle(tester);
      await systemBack(tester);
      expect(find.byType(OnboardingScreen), findsOneWidget);
      expect(navigator(tester).canPop(), isFalse);
    });

    testWidgets('aus der Einlern-Unterseite des Aktivierungsworts: '
        'AppBar- und System-Zurück führen auf den Assistenten', (tester) async {
      await onWakePage(tester);
      for (final viaAppBar in [true, false]) {
        await tapText(tester, 'Einlernen und einschalten');
        unawaited(
          navigator(tester).push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  const WakeEnrollScreen(speakerId: 'sp1', name: 'A'),
            ),
          ),
        );
        await settle(tester);
        expect(find.byType(WakeEnrollScreen), findsOneWidget);
        if (viaAppBar) {
          await tester.tap(find.byTooltip('Zurück').first);
          await settle(tester);
        } else {
          await systemBack(tester);
        }
        expect(find.byType(WakeEnrollScreen), findsNothing);
        expect(find.byType(OnboardingScreen), findsOneWidget);
        expect(navigator(tester).canPop(), isFalse);
      }
    });

    testWidgets('Personalisierung: Stimme einlernen und zurück', (
      tester,
    ) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(
        AppSettings.setupWizardPage,
        'personalization',
      );
      final env = await envOn(storage);
      env.speechModels.installed.add('speaker-campplus');
      await pump(tester, env);
      expect(find.text('Noch keine Stimme eingelernt'), findsOneWidget);
      await tapText(tester, 'Stimme einlernen');
      expect(find.byType(SpeakerScreen), findsOneWidget);
      await systemBack(tester);
      expect(find.text('Noch keine Stimme eingelernt'), findsOneWidget);
    });

    testWidgets(
      'nach dem Abschluss: normale Navigation, auch aus Unterseiten',
      (tester) async {
        final storage = openInMemoryStorage();
        await storage.settings.set(AppSettings.setupWizardDone, true);
        await pump(tester, await envOn(storage));
        expect(find.byType(MainScreen), findsOneWidget);
        unawaited(navigator(tester).pushNamed<void>(AppRoutes.wakeWord));
        await settle(tester);
        unawaited(navigator(tester).pushNamed<void>(AppRoutes.speaker));
        await settle(tester);
        // One step back, not to the root.
        await tester.tap(find.byTooltip('Zurück').first);
        await settle(tester);
        expect(find.byType(MainScreen), findsNothing);
        expect(navigator(tester).canPop(), isTrue);
        await systemBack(tester);
        expect(find.byType(MainScreen), findsOneWidget);
      },
    );

    testWidgets('Abschluss während der Assistent offen ist: sofort normale '
        'Navigation', (tester) async {
      final storage = openInMemoryStorage();
      await storage.settings.set(AppSettings.setupWizardPage, 'done');
      final env = await envOn(storage);
      final c = await pump(tester, env);
      expect(find.text('Alles bereit'), findsOneWidget);
      await tapText(tester, 'Fertig');
      expect(c.read(setupWizardActiveProvider), isFalse);
      unawaited(navigator(tester).pushNamed<void>(AppRoutes.wakeWord));
      await settle(tester);
      unawaited(navigator(tester).pushNamed<void>(AppRoutes.speaker));
      await settle(tester);
      await tester.tap(find.byTooltip('Zurück').first);
      await settle(tester);
      expect(navigator(tester).canPop(), isTrue);
    });
  });
}
