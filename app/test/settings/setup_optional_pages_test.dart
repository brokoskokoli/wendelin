// WP174 part C: the optional pages of the setup wizard (wake word,
// integrations, personalization), the closing page, and back from the menus
// they open.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/setup_status.dart';
import 'package:wendelin/di/setup_wizard.dart';
import 'package:wendelin/di/speaker_providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/ui/settings/integrations_screen.dart';
import 'package:wendelin/ui/settings/speaker/speaker_screen.dart';
import 'package:wendelin/ui/settings/wake/wake_word_screen.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;
import 'onboarding_test.dart' show seedProvider, tapText;
import 'setup_pages_test.dart' show enabled;
import 'setup_wizard_test.dart' show navigator, systemBack;

const _camPlus = 'speaker-campplus';

SpeakerProfile _person() => SpeakerProfile(
  id: 'p1',
  name: 'Anna',
  embeddings: [
    Float32List.fromList([1, 0]),
  ],
  threshold: 0.5,
  createdAt: DateTime(2026),
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  String page, {
  SetupFacts? facts,
  bool people = false,
  bool camPlus = false,
  bool provider = true,
}) async {
  final store = InMemorySpeakerProfileStore();
  if (people) await store.save(_person());
  final env = TestEnv(
    extraOverrides: [
      if (facts != null) setupFactsProvider.overrideWithValue(facts),
      speakerProfileStoreProvider.overrideWithValue(store),
    ],
    startup: StartupSettings(setupWizardDone: false, setupWizardPage: page),
    storedProfiles: true,
  );
  env.speechModels.installed.addAll([
    'whisper-small',
    'silero-vad',
    if (camPlus) _camPlus,
  ]);
  if (provider) await seedProvider(env);
  setView(tester, const Size(390, 1700));
  await tester.pumpWidget(env.app());
  await settle(tester);
  _env = env;
  return ProviderScope.containerOf(
    tester.element(find.byType(OnboardingScreen)),
  );
}

late TestEnv _env;

void main() {
  group('Seite Aktivierungswort (optional)', () {
    testWidgets('nicht eingerichtet: Stand, Menü per Knopf, Ohne fortfahren', (
      tester,
    ) async {
      await _pump(tester, 'wakeWord');
      expect(find.text('Aktivierungswort nicht eingerichtet'), findsOne);
      expect(enabled(tester, 'Ohne fortfahren'), isTrue);
      await tapText(tester, 'Einlernen und einschalten');
      expect(find.byType(WakeWordScreen), findsOneWidget);
      await systemBack(tester);
      expect(find.text('Aktivierungswort nicht eingerichtet'), findsOne);
      await tapText(tester, 'Ohne fortfahren');
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
    });

    testWidgets('eingerichtet und in Ordnung: Weiter ist die Hauptaktion', (
      tester,
    ) async {
      await _pump(
        tester,
        'wakeWord',
        facts: const SetupFacts(
          providerConfigured: true,
          speechReady: true,
          wakeReady: true,
        ),
      );
      expect(
        find.text('Aktivierungswort eingerichtet und in Ordnung'),
        findsOne,
      );
      expect(enabled(tester, 'Weiter'), isTrue);
      expect(find.text('Ohne fortfahren'), findsNothing);
      await tapText(tester, 'Weiter');
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
    });

    testWidgets('Zustand unbekannt (Fehler/Laden): Weiter sperrt nie', (
      tester,
    ) async {
      final c = await _pump(
        tester,
        'wakeWord',
        facts: const SetupFacts(providerConfigured: true, speechReady: true),
      );
      expect(enabled(tester, 'Ohne fortfahren'), isTrue);
      expect(await c.read(setupWizardPageProvider.notifier).advance(), isTrue);
    });
  });

  group('Seite Integrationen (optional)', () {
    testWidgets('Weiter geht sofort, Knopf öffnet das Menü, Zurück hierher', (
      tester,
    ) async {
      await _pump(tester, 'integrations');
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isTrue);
      await tapText(tester, 'Integrationen öffnen');
      expect(find.byType(IntegrationsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück').first);
      await settle(tester);
      expect(find.byType(IntegrationsScreen), findsNothing);
      expect(find.text('Was darf Wendelin?'), findsOneWidget);
      await tapText(tester, 'Weiter');
      expect(find.text('Personalisierung'), findsOneWidget);
    });
  });

  group('Seite Personalisierung (optional)', () {
    testWidgets('ohne Modell: Laden, Fortschritt, Überspringen sperrt nie', (
      tester,
    ) async {
      await _pump(tester, 'personalization');
      expect(enabled(tester, 'Überspringen'), isTrue);
      expect(enabled(tester, 'Herunterladen'), isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Herunterladen'));
      await tester.pump();
      expect(_env.speechModels.running.keys, [_camPlus]);
      expect(enabled(tester, 'Überspringen'), isTrue, reason: 'beim Laden');
    });

    testWidgets('Fehler: nur in der Zeile, Erneut versuchen, Überspringen', (
      tester,
    ) async {
      await _pump(tester, 'personalization');
      await tester.tap(find.widgetWithText(FilledButton, 'Herunterladen'));
      await tester.pump();
      _env.speechModels.fail(
        _camPlus,
        const ModelDownloadException(DownloadErrorKind.network, 'Netz weg.'),
      );
      await settle(tester);
      expect(find.text('Netz weg.'), findsOneWidget);
      expect(enabled(tester, 'Erneut versuchen'), isTrue);
      expect(enabled(tester, 'Überspringen'), isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Erneut versuchen'));
      await tester.pump();
      expect(_env.speechModels.running.keys, [_camPlus]);
    });

    testWidgets('Modell da, keine Stimme: Einlernen öffnet den Ablauf', (
      tester,
    ) async {
      await _pump(tester, 'personalization', camPlus: true);
      expect(find.text('Noch keine Stimme eingelernt'), findsOneWidget);
      expect(find.text('Herunterladen'), findsNothing);
      await tapText(tester, 'Stimme einlernen');
      expect(find.byType(SpeakerScreen), findsOneWidget);
      await systemBack(tester);
      expect(find.text('Noch keine Stimme eingelernt'), findsOneWidget);
      await tapText(tester, 'Überspringen');
      expect(find.text('Alles bereit'), findsOneWidget);
    });

    testWidgets('Stimme eingelernt: Stand und Weiter', (tester) async {
      await _pump(tester, 'personalization', camPlus: true, people: true);
      expect(find.text('Deine Stimme ist eingelernt'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isTrue);
      await tapText(tester, 'Weiter');
      expect(find.text('Alles bereit'), findsOneWidget);
    });
  });

  group('Abschluss', () {
    testWidgets('Zusammenfassung abgehakt, Fertig setzt den Abschluss', (
      tester,
    ) async {
      final c = await _pump(tester, 'done', people: true);
      expect(find.text('Anbieter eingerichtet: Mein Claude'), findsOneWidget);
      expect(find.text('Spracherkennung eingerichtet'), findsOneWidget);
      expect(find.text('Aktivierungswort nicht eingerichtet'), findsOne);
      expect(find.text('Deine Stimme ist eingelernt'), findsOneWidget);
      expect(find.byType(MainScreen), findsNothing);
      await tapText(tester, 'Fertig');
      expect(find.byType(MainScreen), findsOneWidget);
      expect(c.read(setupWizardDoneProvider), isTrue);
      expect(
        await _env.storage.settings.get(AppSettings.setupWizardDone),
        isTrue,
      );
    });

    testWidgets('Pflichtseite offen: Fertig gesperrt, nichts gespeichert', (
      tester,
    ) async {
      final c = await _pump(
        tester,
        'done',
        facts: const SetupFacts(providerConfigured: true),
      );
      expect(enabled(tester, 'Fertig'), isFalse);
      expect(await c.read(setupWizardPageProvider.notifier).finish(), isFalse);
      expect(c.read(setupWizardDoneProvider), isFalse);
    });

    testWidgets('danach: Einstellungsseiten mit normaler Navigation', (
      tester,
    ) async {
      await _pump(tester, 'done');
      await tapText(tester, 'Fertig');
      unawaited(navigator(tester).pushNamed<void>('/settings/voice/speaker'));
      await settle(tester);
      await tester.tap(find.byTooltip('Zurück').first);
      await settle(tester);
      expect(find.byType(MainScreen), findsOneWidget);
    });
  });
}
