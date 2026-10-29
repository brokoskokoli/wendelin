// WP174 part B: the required pages of the setup wizard (welcome, provider,
// speech) and their blocks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/profiles.dart';
import 'package:wendelin/di/setup_status.dart';
import 'package:wendelin/di/setup_wizard.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/settings/provider_setup_screen.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'integrations_screen_test.dart' show settle;
import 'onboarding_test.dart' show firstStart, pumpApp, seedProvider, tapText;

const _parakeet = 'parakeet-tdt-0.6b-v3';

/// The enabled state of the button with [label] (null = not found).
bool? enabled(WidgetTester tester, String label) {
  for (final f in [
    find.widgetWithText(FilledButton, label),
    find.widgetWithText(OutlinedButton, label),
  ]) {
    if (f.evaluate().isEmpty) continue;
    final w = tester.widget(f);
    return (w is FilledButton
            ? w.onPressed
            : (w as OutlinedButton).onPressed) !=
        null;
  }
  return null;
}

void main() {
  group('Seite Willkommen', () {
    testWidgets('kurzer Text, Los geht’s, keine Sprachwahl, kein Zurück', (
      tester,
    ) async {
      await pumpApp(tester, firstStart());
      expect(find.text('Willkommen'), findsOneWidget);
      expect(find.textContaining('persönlicher Sprachassistent'), findsOne);
      expect(find.text('App-Sprache der Oberfläche'), findsNothing);
      expect(find.text('Deutsch'), findsNothing);
      expect(find.byTooltip('Zurück'), findsNothing);
      await tapText(tester, 'Los geht’s');
      expect(find.text('KI-Anbieter'), findsOneWidget);
    });
  });

  group('Seite KI-Anbieter (Pflicht)', () {
    testWidgets('ohne Anbieter: Hinweis, Weiter gesperrt, Dialog per Knopf', (
      tester,
    ) async {
      final c = await pumpApp(tester, firstStart(page: 'provider'));
      expect(find.text('KI-Anbieter'), findsOneWidget);
      expect(find.text('Noch kein Anbieter eingerichtet'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isFalse);
      expect(await c.read(setupWizardPageProvider.notifier).advance(), isFalse);
      await tapText(tester, 'Anbieter eintragen');
      expect(find.byType(ProviderSetupScreen), findsOneWidget);
    });

    testWidgets('mit Anbieter: Name auf der Seite, Weiter geht', (
      tester,
    ) async {
      final env = firstStart(page: 'provider');
      await seedProvider(env);
      await pumpApp(tester, env);
      expect(find.text('Anbieter eingerichtet: Mein Claude'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isTrue);
      await tapText(tester, 'Weiter');
      expect(find.text('Spracherkennung'), findsOneWidget);
    });

    testWidgets('Fehler beim Lesen: unbekannt sperrt Weiter trotz Anbieter', (
      tester,
    ) async {
      final env = firstStart(page: 'provider');
      await seedProvider(env);
      final c = await pumpApp(tester, env);
      expect(enabled(tester, 'Weiter'), isTrue);
      await tester.runAsync(env.storage.close);
      c.invalidate(profilesProvider);
      await settle(tester);
      expect(c.read(profilesProvider).hasError, isTrue);
      expect(find.textContaining('Anbieter eingerichtet:'), findsNothing);
      expect(enabled(tester, 'Weiter'), isFalse);
      expect(await c.read(setupWizardPageProvider.notifier).advance(), isFalse);
    });
  });

  group('Seite Spracherkennung (Pflicht)', () {
    Future<ProviderContainer> speechPage(
      WidgetTester tester,
      TestEnv env,
    ) async {
      await seedProvider(env);
      return pumpApp(tester, env);
    }

    testWidgets('Standard Parakeet, Silero darunter, Weiter gesperrt', (
      tester,
    ) async {
      final env = firstStart(page: 'speech');
      final c = await speechPage(tester, env);
      expect(c.read(voiceSettingsProvider).value!.sttModel, _parakeet);
      expect(
        (await env.storage.settings.get(voiceSettingsKey))!.sttModel,
        _parakeet,
      );
      expect(find.text('Erkennungsmodell'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('sttModelPicker')),
          matching: find.text('Parakeet v3'),
        ),
        findsOneWidget,
      );
      expect(find.text('Silero VAD'), findsOneWidget);
      expect(enabled(tester, 'Herunterladen'), isTrue);
      expect(enabled(tester, 'Weiter'), isFalse);
      expect(find.textContaining('Noch nötig: Parakeet v3'), findsOneWidget);
    });

    testWidgets('bewusst gewähltes Whisper small wird nicht überschrieben', (
      tester,
    ) async {
      final env = firstStart(page: 'speech');
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-small'),
      );
      final c = await speechPage(tester, env);
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-small');
      expect(find.textContaining('Noch nötig: Whisper small'), findsOne);
    });

    testWidgets('wenig RAM: Whisper base vorausgewählt, Hinweis', (
      tester,
    ) async {
      final env = firstStart(page: 'speech', memory: 3 * 1024 * 1024 * 1024);
      final c = await speechPage(tester, env);
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-base');
      expect(
        (await env.storage.settings.get(voiceSettingsKey))!.sttModel,
        'whisper-base',
      );
      expect(find.textContaining('Wenig Arbeitsspeicher (3,0 GB)'), findsOne);
    });

    testWidgets('genug RAM: kein Hinweis', (tester) async {
      final c = await speechPage(
        tester,
        firstStart(page: 'speech', memory: 8 * 1024 * 1024 * 1024),
      );
      expect(c.read(voiceSettingsProvider).value!.sttModel, _parakeet);
      expect(find.textContaining('Wenig Arbeitsspeicher'), findsNothing);
    });

    testWidgets('Auswahl zeigt nur Erkennungsmodelle und setzt sttModel', (
      tester,
    ) async {
      final c = await speechPage(tester, firstStart(page: 'speech'));
      await tester.tap(find.byKey(const ValueKey('sttModelPicker')));
      await settle(tester);
      for (final n in ['Parakeet v3', 'Whisper base', 'Whisper small']) {
        expect(find.text(n), findsWidgets, reason: n);
      }
      expect(find.text('Silero VAD'), findsOneWidget, reason: 'nur die Zeile');
      await tester.tap(find.text('Whisper small').last);
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-small');
    });

    testWidgets('Herunterladen: beide laden, Fortschritt, dann Weiter', (
      tester,
    ) async {
      final env = firstStart(page: 'speech');
      final c = await speechPage(tester, env);
      final m = env.speechModels;
      await tester.tap(find.widgetWithText(FilledButton, 'Herunterladen'));
      await tester.pump();
      expect(m.running.keys, {_parakeet, 'silero-vad'});
      expect(enabled(tester, 'Lädt …'), isFalse);
      expect(enabled(tester, 'Weiter'), isFalse);
      // The selection is locked while loading.
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const ValueKey('sttModelPicker')),
            )
            .enabled,
        isFalse,
      );

      m.progress(_parakeet, 0.5);
      m.progress('silero-vad', 0.25);
      await tester.pump();
      expect(find.textContaining('Lädt … 50 % von'), findsOneWidget);
      expect(find.textContaining('Lädt … 25 % von'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is LinearProgressIndicator &&
              w.semanticsLabel == 'Fortschritt Parakeet v3 – groß, schnell',
        ),
        findsOneWidget,
      );

      m.finish(_parakeet);
      await settle(tester);
      expect(enabled(tester, 'Weiter'), isFalse, reason: 'VAD fehlt noch');
      m.finish('silero-vad');
      await settle(tester);
      expect(find.text('Bereit'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isTrue);
      await tapText(tester, 'Weiter');
      expect(c.read(setupWizardPageProvider), SetupPage.wakeWord);
    });

    testWidgets('Fehler: Meldung, Erneut versuchen lädt nur das Fehlende', (
      tester,
    ) async {
      final env = firstStart(page: 'speech');
      env.speechModels.installed.add('silero-vad');
      await speechPage(tester, env);
      await tester.tap(find.widgetWithText(FilledButton, 'Herunterladen'));
      await tester.pump();
      final m = env.speechModels;
      expect(m.running.keys, [_parakeet]);
      m.fail(
        _parakeet,
        const ModelDownloadException(DownloadErrorKind.network, 'Netz weg.'),
      );
      await settle(tester);
      expect(
        find.text('Netz weg.'),
        findsOneWidget,
        reason: 'nur in der Zeile',
      );
      expect(enabled(tester, 'Weiter'), isFalse);
      expect(enabled(tester, 'Erneut versuchen'), isTrue);
      await tester.tap(find.widgetWithText(FilledButton, 'Erneut versuchen'));
      await tester.pump();
      expect(m.running.keys, [_parakeet]);
    });

    testWidgets('Teil-Download wird beim Öffnen fortgesetzt', (tester) async {
      final env = firstStart(page: 'speech');
      env.speechModels.partial.add(_parakeet);
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: _parakeet),
      );
      await speechPage(tester, env);
      expect(env.speechModels.running.keys, [_parakeet]);
      expect(enabled(tester, 'Weiter'), isFalse);
    });

    testWidgets('Abbruch: Zeile zeigt Fortsetzen, Weiter bleibt gesperrt', (
      tester,
    ) async {
      final env = firstStart(page: 'speech');
      await speechPage(tester, env);
      await tester.tap(find.widgetWithText(FilledButton, 'Herunterladen'));
      await tester.pump();
      env.speechModels.partial.add(_parakeet);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Abbrechen').first);
      await settle(tester);
      expect(find.widgetWithText(OutlinedButton, 'Fortsetzen'), findsWidgets);
      expect(enabled(tester, 'Weiter'), isFalse);
    });

    testWidgets('nur das Modell, ohne Silero: Weiter gesperrt', (tester) async {
      final env = firstStart(page: 'speech');
      env.speechModels.installed.add(_parakeet);
      final c = await speechPage(tester, env);
      expect(find.textContaining('Noch nötig: Silero VAD'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isFalse);
      expect(await c.read(setupWizardPageProvider.notifier).advance(), isFalse);
    });

    testWidgets('bestehendes Whisper small bleibt, Seite ist abgehakt', (
      tester,
    ) async {
      final env = firstStart(page: 'speech', withSpeech: true);
      final c = await speechPage(tester, env);
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-small');
      expect(find.text('Bereit'), findsOneWidget);
      expect(enabled(tester, 'Weiter'), isTrue);
    });

    testWidgets('Fehler beim Lesen der Einstellungen: Weiter gesperrt', (
      tester,
    ) async {
      final env = firstStart(page: 'speech', withSpeech: true);
      final c = await speechPage(tester, env);
      expect(enabled(tester, 'Weiter'), isTrue);
      await tester.runAsync(env.storage.close);
      c.invalidate(voiceSettingsProvider);
      await settle(tester);
      expect(c.read(voiceSettingsProvider).hasError, isTrue);
      expect(enabled(tester, 'Weiter'), isNot(isTrue));
      expect(await c.read(setupWizardPageProvider.notifier).advance(), isFalse);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });
  });
}
