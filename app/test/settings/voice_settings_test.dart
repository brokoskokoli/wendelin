import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/agent_factory.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/design/design.dart' show CheckStatusIcon, WSwitch;
import 'package:wendelin/ui/onboarding/voice_download_step.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/ui/settings/model_download_row.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin/ui/settings/voice_screen.dart';
import 'package:wendelin/ui/settings/voice_spoken_section.dart';
import 'package:wendelin/ui/settings/voice_voices_screen.dart';
import 'package:wendelin_agent/wendelin_agent.dart' show AgentConfig;
import 'package:wendelin_core/wendelin_core.dart' show SpokenVersion;
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart' show settle;

const _tall = Size(390, 2600);

Future<ProviderContainer> pumpScreen(
  WidgetTester tester,
  TestEnv env,
  Widget screen,
) async {
  setView(tester, _tall);
  await tester.pumpWidget(env.app(home: screen));
  await settle(tester);
  return ProviderScope.containerOf(tester.element(find.byWidget(screen)));
}

/// The progress bar of [model].
Finder progressOf(String model) => find.byWidgetPredicate(
  (w) =>
      w is LinearProgressIndicator && w.semanticsLabel == 'Fortschritt $model',
);

/// The action button of the row titled [model].
Finder action(String model, String label) => find.descendant(
  of: find.ancestor(
    of: find.text(model),
    matching: find.byType(ModelDownloadRow),
  ),
  matching: find.widgetWithText(OutlinedButton, label),
);

void main() {
  const base = 'Whisper base – schnell, für schwache Geräte';
  const small = 'Whisper small – genauer (empfohlen)';
  const vad = 'Silero VAD';

  group('Onboarding-Schritt „Spracherkennung laden“', () {
    /// The filled button with [label], if any.
    FilledButton? primary(WidgetTester tester, String label) {
      final f = find.widgetWithText(FilledButton, label);
      return f.evaluate().isEmpty ? null : tester.widget<FilledButton>(f);
    }

    testWidgets('ein Ladeweg: Silero kommt mit, „Noch nötig“, dann Weiter', (
      tester,
    ) async {
      final env = TestEnv();
      var next = 0;
      final step = VoiceDownloadStep(onNext: () => next++);
      await pumpScreen(tester, env, step);
      final m = env.speechModels;

      expect(find.text('Spracherkennung laden'), findsOneWidget);
      // B3: no buttons per row, Silero no row of its own.
      expect(find.byType(OutlinedButton), findsOneWidget); // „Später“
      expect(find.byType(ModelDownloadRow), findsNothing);
      expect(find.text(vad), findsNothing);
      expect(
        find.textContaining('Silero VAD gehört dazu (0,6 MB)'),
        findsOneWidget,
      );
      expect(
        find.text('Noch nötig: Whisper small (375 MB) und Silero VAD (0,6 MB)'),
        findsOneWidget,
      );
      expect(primary(tester, 'Weiter'), isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Laden'));
      await tester.pump();
      expect(m.running.keys, {'whisper-small', 'silero-vad'});
      expect(primary(tester, 'Lädt …')!.onPressed, isNull);
      expect(find.text('Im Hintergrund weiterladen'), findsOneWidget);

      m.progress('whisper-small', 0.5);
      await tester.pump();
      expect(find.text('Lädt … 50 % von 375 MB'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        progressOf('Spracherkennung'),
      );
      final smallBytes = SpeechModelCatalog.whisperSmall.sizeBytes;
      final vadBytes = SpeechModelCatalog.sileroVad.sizeBytes;
      expect(
        bar.value,
        closeTo(0.5 * smallBytes / (smallBytes + vadBytes), 0.001),
      );

      m.finish('silero-vad');
      await settle(tester);
      expect(
        find.text('Noch nötig: Whisper small (375 MB)'),
        findsOneWidget,
        reason: 'Silero fertig, small fehlt noch',
      );
      expect(primary(tester, 'Weiter'), isNull);

      m.finish('whisper-small');
      await settle(tester);
      expect(find.text('Bereit'), findsOneWidget);
      expect(find.text('Später'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
      expect(next, 1);
    });

    // B3: „Weiter“ is active exactly when the chosen combination is
    // installed; otherwise one load button and „Noch nötig: …“.
    for (final (whisper, silero, ready, button, status) in [
      (
        'absent',
        'absent',
        false,
        'Laden',
        'Noch nötig: Whisper small (375 MB) und Silero VAD (0,6 MB)',
      ),
      (
        'installed',
        'absent',
        false,
        'Laden',
        'Noch nötig: Silero VAD (0,6 MB)',
      ),
      (
        'absent',
        'installed',
        false,
        'Laden',
        'Noch nötig: Whisper small (375 MB)',
      ),
      (
        'partial',
        'installed',
        false,
        'Lädt …',
        'Noch nötig: Whisper small (375 MB)',
      ),
      (
        'installed',
        'partial',
        false,
        'Lädt …',
        'Noch nötig: Silero VAD (0,6 MB)',
      ),
      ('installed', 'installed', true, 'Weiter', 'Bereit'),
    ]) {
      testWidgets('Zustand small $whisper, Silero $silero', (tester) async {
        final env = TestEnv();
        final m = env.speechModels;
        for (final (id, phase) in [
          ('whisper-small', whisper),
          ('silero-vad', silero),
        ]) {
          if (phase == 'installed') m.installed.add(id);
          if (phase == 'partial') m.partial.add(id);
        }
        await env.storage.settings.set(
          voiceSettingsKey,
          const VoiceSettings(sttModel: 'whisper-small'),
        );
        await pumpScreen(tester, env, VoiceDownloadStep(onNext: () {}));
        expect(find.text(status), findsOneWidget);
        final b = primary(tester, button)!;
        expect(b.onPressed != null, button != 'Lädt …');
        expect(primary(tester, 'Weiter') != null, ready);
        expect(
          find.text(ready ? 'Später' : 'Weiter'),
          findsNothing,
          reason: 'entweder Weiter oder Laden mit Später/Hintergrund',
        );
      });
    }

    testWidgets('Fehler: Meldung, „Erneut laden“ lädt nur das Fehlende', (
      tester,
    ) async {
      final env = TestEnv();
      final m = env.speechModels..installed.add('silero-vad');
      await pumpScreen(tester, env, VoiceDownloadStep(onNext: () {}));
      await tester.tap(find.widgetWithText(FilledButton, 'Laden'));
      await tester.pump();
      expect(m.running.keys, ['whisper-small']);
      m.fail(
        'whisper-small',
        const ModelDownloadException(DownloadErrorKind.network, 'Netz weg.'),
      );
      await settle(tester);
      expect(find.text('Netz weg.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Erneut laden'));
      await tester.pump();
      expect(m.running.keys, ['whisper-small']);
    });

    test('Größen: unter 10 MB mit Komma', () {
      expect(sizeLabel(643854), '0,6 MB');
      expect(sizeLabel(9949999), '9,9 MB');
      expect(sizeLabel(160609290), '161 MB');
    });

    testWidgets('angefangener Download wird beim Öffnen fortgesetzt', (
      tester,
    ) async {
      final env = TestEnv();
      env.speechModels.partial.add('whisper-small');
      await pumpScreen(tester, env, VoiceDownloadStep(onNext: () {}));
      expect(env.speechModels.running.keys, ['whisper-small']);
    });

    testWidgets('base wählen, Später', (tester) async {
      final env = TestEnv();
      var next = 0;
      final c = await pumpScreen(
        tester,
        env,
        VoiceDownloadStep(onNext: () => next++),
      );
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-small');
      env.speechModels.installed.add('whisper-base');
      await c.read(modelStatesProvider.notifier).refresh();
      await settle(tester);
      await tester.tap(find.text(base));
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-base');
      expect(
        (await env.storage.settings.get(voiceSettingsKey))!.sttModel,
        'whisper-base',
      );
      await tester.tap(find.text('Später'));
      expect(next, 1);
    });
  });

  group('Fehler beim Download', () {
    for (final (name, error, text) in [
      (
        'Prüfsumme',
        const ModelDownloadException(
          DownloadErrorKind.checksum,
          'Prüfsumme von base-encoder.int8.onnx stimmt nicht; die Datei wurde '
          'verworfen.',
        ),
        'Prüfsumme von base-encoder.int8.onnx stimmt nicht',
      ),
      (
        'Speicherplatz',
        const InsufficientSpaceException(
          requiredBytes: 300000000,
          freeBytes: 100000000,
        ),
        'Zu wenig Speicherplatz: 300 MB nötig, 100 MB frei.',
      ),
      (
        'Archiv',
        const ArchiveRejected('Unsicherer Pfad im Archiv: ../x'),
        'Unsicherer Pfad',
      ),
      ('unbekannt', StateError('x'), 'Der Download ist fehlgeschlagen.'),
    ]) {
      testWidgets(name, (tester) async {
        final env = TestEnv();
        await pumpScreen(tester, env, const VoiceScreen());
        await tester.tap(action(base, 'Laden'));
        await tester.pump();
        env.speechModels.fail('whisper-base', error);
        await settle(tester);
        expect(find.textContaining(text), findsOneWidget);
        expect(action(base, 'Erneut laden'), findsOneWidget);
        await tester.tap(action(base, 'Erneut laden'));
        await tester.pump();
        expect(find.textContaining(text), findsNothing);
        expect(env.speechModels.running.keys, ['whisper-base']);
      });
    }

    testWidgets('Fehler mit Rest: Fortsetzen statt Laden', (tester) async {
      final env = TestEnv();
      await pumpScreen(tester, env, const VoiceScreen());
      await tester.tap(action(vad, 'Laden'));
      await tester.pump();
      env.speechModels.fail(
        'silero-vad',
        const ModelDownloadException(DownloadErrorKind.network, 'Netz weg.'),
        keepPartial: true,
      );
      await settle(tester);
      expect(find.text('Netz weg.'), findsOneWidget);
      expect(action(vad, 'Fortsetzen'), findsOneWidget);
    });

    testWidgets('Entpacken zeigt unbestimmten Fortschritt', (tester) async {
      final env = TestEnv();
      await pumpScreen(tester, env, const VoiceVoicesScreen());
      await tester.tap(action('Deutsch – Thorsten (männlich)', 'Laden'));
      await tester.pump();
      env.speechModels.unpack('tts-de-thorsten');
      await tester.pump();
      expect(find.text('Wird entpackt …'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        progressOf('Deutsch – Thorsten (männlich)'),
      );
      expect(bar.value, isNull);
      expect(
        action('Deutsch – Thorsten (männlich)', 'Abbrechen'),
        findsNothing,
      );
      env.speechModels.finish('tts-de-thorsten');
      await settle(tester);
    });
  });

  group('Einstellungen → Sprache', () {
    TestEnv env0() {
      final env = TestEnv(startup: const StartupSettings(language: 'fr'));
      env.systemTts.available = false;
      env.speechModels.installed.addAll(['whisper-base', 'silero-vad']);
      return env;
    }

    testWidgets('über die Übersicht erreichbar', (tester) async {
      setView(tester, _tall);
      final env = env0();
      await tester.pumpWidget(env.app(home: const SettingsScreen()));
      await settle(tester);
      await tester.tap(find.text('Sprache'));
      await settle(tester);
      expect(find.byType(VoiceScreen), findsOneWidget);
      expect(AppRoutes.voice, '/settings/voice');
    });

    testWidgets('Modell, Sprache, Ausgabe, Tempo, Feinabstimmung speichern', (
      tester,
    ) async {
      final env = env0();
      final c = await pumpScreen(tester, env, const VoiceScreen());
      VoiceSettings saved() => c.read(voiceSettingsProvider).value!;

      // Nothing stored, only base installed (before WP33): base stays.
      expect(saved().sttModel, 'whisper-base');
      expect(await env.storage.settings.get(voiceSettingsKey), isNull);
      // small is not installed: tapping does not select it.
      await tester.tap(find.text(small).first);
      await settle(tester);
      expect(saved().sttModel, 'whisper-base');

      expect(find.text('Wie die App (Français)'), findsOneWidget);
      await tester.tap(find.text('Automatisch erkennen'));
      await settle(tester);
      expect(saved().sttLanguage, VoiceSettings.detect);
      await tester.tap(find.text('English'));
      await settle(tester);
      expect(saved().effectiveLanguage('fr'), 'en');

      await tester.tap(find.text('Offline-Stimme'));
      await settle(tester);
      expect(saved().tts, TtsPreference.sherpa);
      expect(
        find.text('Wendelin spricht mit der Offline-Stimme.'),
        findsOneWidget,
      );

      await tester.tap(find.text('1,2×'));
      await tester.tap(find.text('300 ms'));
      await tester.tap(find.text('0,6'));
      await settle(tester);
      expect(saved().ttsRate, 1.2);
      expect(saved().minSpeechMs, 300);
      expect(saved().vadThreshold, 0.6);
      expect(saved().endpoint.minSpeech, const Duration(milliseconds: 300));
      expect(await env.storage.settings.get(voiceSettingsKey), saved());

      final config = await c.read(voicePipelineConfigProvider.future);
      expect(config.language, 'en');
      expect(config.rate, 1.2);
      expect(config.endpoint.minSpeech, const Duration(milliseconds: 300));
    });

    testWidgets('ohne Systemstimme: Hinweis auf Offline-Stimme', (
      tester,
    ) async {
      await pumpScreen(tester, env0(), const VoiceScreen());
      expect(
        find.text('Wendelin spricht mit der Offline-Stimme.'),
        findsOneWidget,
        reason: 'automatisch fällt ohne Systemstimme auf sherpa zurück',
      );
    });

    testWidgets('Systemstimme wählen, Probe hören', (tester) async {
      final env = env0();
      env.systemTts.available = true;
      final system = env.systemTts;
      final c = await pumpScreen(tester, env, const VoiceScreen());
      await tester.tap(find.text('Standard der Sprache'));
      await settle(tester);
      await tester.tap(find.text('fake-fr (fr)'));
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.ttsVoice, 'fake-fr');
      await tester.tap(find.text('Probe hören'));
      await settle(tester);
      expect(system.calls.single.voice, 'fake-fr');
      expect(system.calls.single.language, 'fr');

      await tester.tap(find.text('fake-fr'));
      await settle(tester);
      await tester.tap(find.text('Standard der Sprache').last);
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.ttsVoice, isNull);
    });

    // B13: the sample comes in the spoken language.
    for (final (title, lang, text) in [
      ('Français', 'fr', 'Bonjour, je suis Wendelin.'),
      ('English', 'en', 'Hello, I am Wendelin.'),
      ('Deutsch', 'de', 'Hallo, ich bin Wendelin.'),
    ]) {
      testWidgets('Probe hören in fester Sprache $title', (tester) async {
        final env = env0();
        final sherpa = env.sherpaTts;
        await pumpScreen(tester, env, const VoiceScreen());
        await tester.tap(find.text(title));
        await settle(tester);
        await tester.tap(find.text('Probe hören'));
        await settle(tester);
        expect(sherpa.calls.single.language, lang);
        expect(sherpa.calls.single.text, text);
      });
    }

    testWidgets('Probe hören: „Automatisch“ nimmt die App-Sprache', (
      tester,
    ) async {
      final env = env0();
      final sherpa = env.sherpaTts;
      final c = await pumpScreen(tester, env, const VoiceScreen());
      await tester.tap(find.text('Automatisch erkennen'));
      await settle(tester);
      await tester.tap(find.text('Probe hören'));
      await settle(tester);
      expect(sherpa.calls.single.language, c.read(languageProvider));
    });

    test('„Stopp schließt das Overlay“: Standard an, wird gespeichert', () {
      expect(const VoiceSettings().stopClosesOverlay, isTrue);
      final off = const VoiceSettings().copyWith(stopClosesOverlay: false);
      expect(VoiceSettings.fromJson(off.toJson()).stopClosesOverlay, isFalse);
      expect(VoiceSettings.fromJson(const {}).stopClosesOverlay, isTrue);
    });

    testWidgets('Schalter „Stopp schließt das Overlay“', (tester) async {
      final c = await pumpScreen(tester, env0(), const VoiceScreen());
      await tester.ensureVisible(find.text('Stopp schließt das Overlay'));
      await tester.tap(find.byType(WSwitch).first);
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.stopClosesOverlay, isFalse);
    });

    test('„Sprechfassung“: Standard aus, wird gespeichert, alter Schalter '
        'wandert', () {
      expect(const VoiceSettings().spokenVersion, SpokenVersion.off);
      final on = const VoiceSettings().copyWith(
        spokenVersion: SpokenVersion.checked,
      );
      expect(
        VoiceSettings.fromJson(on.toJson()).spokenVersion,
        SpokenVersion.checked,
      );
      expect(
        VoiceSettings.fromJson(const {'twoVersions': true}).spokenVersion,
        SpokenVersion.protected,
      );
    });

    testWidgets('Auswahl „Sprechfassung“ mit Erklärungen, Warnung bei '
        '„Immer“ und Wirkung auf den Agenten', (tester) async {
      final c = await pumpScreen(tester, env0(), const VoiceScreen());
      AgentConfig config() =>
          (c.read(agentFactoryProvider) as AgentFactory).config;
      expect(config().spokenVersion, SpokenVersion.off);
      await tester.ensureVisible(find.text('Mit KI-Prüfung'));
      for (final t in spokenVersionTexts.values) {
        expect(find.text(t.$1), findsOneWidget);
        expect(find.text(t.$2), findsOneWidget);
      }
      expect(find.text(spokenVersionAlwaysWarning), findsNothing);
      for (final level in SpokenVersion.values) {
        await tester.tap(find.byKey(ValueKey('spoken-${level.name}')));
        await settle(tester);
        expect(c.read(voiceSettingsProvider).value!.spokenVersion, level);
        expect(config().spokenVersion, level);
        expect(
          find.text(spokenVersionAlwaysWarning),
          level == SpokenVersion.always ? findsOneWidget : findsNothing,
        );
      }
    });

    test('Sprache und Text der Probe', () {
      const fixed = VoiceSettings(sttLanguage: 'fr');
      expect(sampleLanguage(fixed, 'de'), 'fr');
      expect(sampleLanguage(const VoiceSettings(), 'en'), 'en');
      expect(
        sampleLanguage(const VoiceSettings(sttLanguage: 'auto'), 'de'),
        'de',
      );
      expect(sampleText('fr-FR'), 'Bonjour, je suis Wendelin.');
      expect(sampleText('xx'), 'Hallo, ich bin Wendelin.');
    });

    testWidgets('Modell löschen nach Rückfrage', (tester) async {
      final env = env0();
      await pumpScreen(tester, env, const VoiceScreen());
      await tester.tap(action(base, 'Löschen'));
      await settle(tester);
      expect(find.text('$base löschen?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await settle(tester);
      expect(env.speechModels.deleted, ['whisper-base']);
      expect(action(base, 'Laden'), findsOneWidget);
      expect(
        find.textContaining('braucht Wendelin das gewählte'),
        findsOneWidget,
      );
    });

    testWidgets('Lizenzen inklusive Pflicht-Attribution', (tester) async {
      await pumpScreen(tester, env0(), const VoiceScreen());
      await tester.scrollUntilVisible(
        find.textContaining('SIWIS French Speech Synthesis'),
        200,
      );
      expect(
        find.textContaining('SIWIS French Speech Synthesis'),
        findsOneWidget,
      );
      expect(find.textContaining('CC0 (Thorsten-Voice)'), findsOneWidget);
    });

    testWidgets('Mikrofon: Erklärung vor der Android-Abfrage', (tester) async {
      final env = env0();
      final mic = env.microphone..granted = false;
      await pumpScreen(tester, env, const VoiceScreen());
      expect(find.text('nicht erlaubt'), findsOneWidget);
      expect(mic.requests, [false]);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Erlauben'));
      await settle(tester);
      expect(find.text('Mikrofon erlauben?'), findsOneWidget);
      expect(find.textContaining('verlässt es nicht'), findsOneWidget);
      await tester.tap(find.text('Nicht jetzt'));
      await settle(tester);
      expect(mic.requests, everyElement(isFalse));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Erlauben'));
      await settle(tester);
      mic.granted = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Erlauben'));
      await settle(tester);
      expect(mic.requests, contains(true));
      expect(find.text('erlaubt'), findsOneWidget);
    });

    testWidgets('Mikrofon abgelehnt: Hinweis auf Android-Einstellungen', (
      tester,
    ) async {
      final env = env0();
      env.microphone.granted = false;
      await pumpScreen(tester, env, const VoiceScreen());
      await tester.tap(find.widgetWithText(OutlinedButton, 'Erlauben'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Erlauben'));
      await settle(tester);
      expect(find.textContaining('Android-Einstellungen'), findsOneWidget);
      expect(env.microphone.requests, contains(true));
    });
  });

  group('Standardmodell (WP33)', () {
    const gib = 1024 * 1024 * 1024;
    TestEnv envWith({Iterable<String> installed = const [], int? memory}) {
      final env = TestEnv(
        extraOverrides: [
          deviceMemoryProvider.overrideWith((ref) async => memory),
        ],
      );
      env.speechModels.installed.addAll(installed);
      return env;
    }

    Future<String> model(TestEnv env) async =>
        (await env.container().read(voiceSettingsProvider.future)).sttModel;

    for (final (name, installed, memory, expected) in [
      ('frisch: small', <String>[], null, 'whisper-small'),
      (
        'frisch, 4-GB-Gerät: small',
        <String>[],
        (3.7 * gib).round(),
        'whisper-small',
      ),
      ('frisch, wenig RAM: base', <String>[], 3 * gib, 'whisper-base'),
      ('nur base installiert: base', ['whisper-base'], null, 'whisper-base'),
      (
        'base und small installiert: small',
        ['whisper-base', 'whisper-small'],
        null,
        'whisper-small',
      ),
      (
        'wenig RAM, small installiert: small',
        ['whisper-small'],
        2 * gib,
        'whisper-small',
      ),
    ]) {
      test(name, () async {
        expect(
          await model(envWith(installed: installed, memory: memory)),
          expected,
        );
      });
    }

    test('gespeicherte M2-Einstellungen mit base bleiben base', () async {
      final env = envWith(installed: ['whisper-base', 'whisper-small']);
      await env.storage.settings.set(
        voiceSettingsKey,
        VoiceSettings.fromJson({'sttModel': 'whisper-base', 'tts': 'system'}),
      );
      expect(await model(env), 'whisper-base');
    });

    const hint = 'Empfohlen: small (genauer)';
    testWidgets('nur base installiert: Hinweis auf small', (tester) async {
      final env = envWith(installed: ['whisper-base', 'silero-vad']);
      await pumpScreen(tester, env, const VoiceScreen());
      expect(
        find.text(
          '$hint, '
          '${megabytes(SpeechModelCatalog.whisperSmall.sizeBytes)} laden.',
        ),
        findsOneWidget,
      );
      // Mikrofon bleibt nutzbar: kein Hinweis auf fehlende Modelle.
      expect(
        find.textContaining('braucht Wendelin das gewählte'),
        findsNothing,
      );
    });

    for (final (name, installed, memory) in [
      ('small aktiv', ['whisper-small', 'silero-vad'], null),
      ('wenig RAM', ['whisper-base', 'silero-vad'], 3 * gib),
    ]) {
      testWidgets('kein Hinweis: $name', (tester) async {
        await pumpScreen(
          tester,
          envWith(installed: installed, memory: memory),
          const VoiceScreen(),
        );
        expect(find.textContaining(hint), findsNothing);
      });
    }

    testWidgets('Onboarding wählt small vor, Texte', (tester) async {
      final env = envWith(memory: 8 * gib);
      final c = await pumpScreen(tester, env, VoiceDownloadStep(onNext: () {}));
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-small');
      expect(find.text(small), findsOneWidget);
      expect(find.text(base), findsOneWidget);
      expect(find.textContaining('genauer (empfohlen)'), findsOneWidget);
      expect(
        find.textContaining('schnell, für schwache Geräte'),
        findsOneWidget,
      );
      expect(find.textContaining('wenig Arbeitsspeicher'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Laden'));
      await tester.pump();
      expect(env.speechModels.running.keys, {'whisper-small', 'silero-vad'});
    });

    testWidgets('Onboarding bei wenig RAM: base mit Begründung', (
      tester,
    ) async {
      final env = envWith(memory: 3 * gib);
      final c = await pumpScreen(tester, env, VoiceDownloadStep(onNext: () {}));
      expect(c.read(voiceSettingsProvider).value!.sttModel, 'whisper-base');
      expect(
        find.text(
          'Vorausgewählt ist „base“, weil das Gerät wenig Arbeitsspeicher '
          'hat (3,0 GB). „small“ braucht beim Erkennen deutlich mehr '
          'Speicher.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Laden'));
      await tester.pump();
      expect(env.speechModels.running.keys, {'whisper-base', 'silero-vad'});
    });
  });

  group('Einstellungen → Sprache → Stimmen (WP66)', () {
    Finder probe(String lang) => find.byKey(Key('probe-$lang'));

    testWidgets('Stimmen je Sprache wählen, löschen, Probe hören', (
      tester,
    ) async {
      final env = TestEnv();
      env.speechModels.installed.addAll(['tts-de-thorsten', 'tts-de-kerstin']);
      final c = await pumpScreen(tester, env, const VoiceVoicesScreen());
      for (final name in [
        'Deutsch – Thorsten (männlich)',
        'Deutsch – Kerstin (weiblich)',
        'Français – Siwis (weiblich)',
        'Français – Gilles (männlich)',
        'English – LJSpeech (weiblich)',
        'English – Joe (männlich)',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.byType(ModelDownloadRow), findsNWidgets(6));
      // Default: first voice of the language; no voice loaded -> no sample.
      expect(
        c.read(voiceSettingsProvider).value!.sherpaVoiceFor('de'),
        'tts-de-thorsten',
      );
      expect(probe('fr'), findsNothing);
      expect(probe('de'), findsOneWidget);
      // One play button per language, on the chosen voice only.
      expect(find.byTooltip('Probe hören'), findsOneWidget);
      expect(find.text('Probe hören'), findsNothing);

      await tester.tap(find.text('Deutsch – Kerstin (weiblich)'));
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.sherpaVoices, {
        'de': 'tts-de-kerstin',
      });
      await tester.tap(probe('de'));
      await settle(tester);
      final call = env.sherpaTts.calls.single;
      expect((call.voice, call.language), ('tts-de-kerstin', 'de'));
      expect(call.text, 'Hallo, ich bin Wendelin.');

      // Not loaded voices are not selectable; loading is offered.
      await tester.tap(find.text('English – Joe (männlich)'));
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.sherpaVoices.keys, ['de']);
      expect(action('English – Joe (männlich)', 'Laden'), findsOneWidget);
      expect(
        action('Deutsch – Thorsten (männlich)', 'Löschen'),
        findsOneWidget,
      );
    });

    /// Whether the row titled [model] shows the check mark.
    bool checked(String model) => find
        .descendant(
          of: find.ancestor(
            of: find.text(model),
            matching: find.byType(ModelDownloadRow),
          ),
          matching: find.byType(CheckStatusIcon),
        )
        .evaluate()
        .isNotEmpty;

    const thorsten = 'Deutsch – Thorsten (männlich)';
    const kerstin = 'Deutsch – Kerstin (weiblich)';

    testWidgets('gewählte Stimme nicht geladen: Haken und Probe bei der '
        'wirksamen Stimme, mit Hinweis', (tester) async {
      final env = TestEnv();
      env.speechModels.installed.add('tts-de-thorsten');
      final c = await pumpScreen(tester, env, const VoiceVoicesScreen());
      await c
          .read(voiceSettingsProvider.notifier)
          .change((s) => s.copyWith(sherpaVoices: {'de': 'tts-de-kerstin'}));
      await settle(tester);
      expect(checked(thorsten), isTrue);
      expect(checked(kerstin), isFalse);
      expect(
        find.text('Gewählte Stimme nicht geladen – es spricht $thorsten.'),
        findsOneWidget,
      );
      await tester.tap(probe('de'));
      await settle(tester);
      expect(env.sherpaTts.calls.single.voice, 'tts-de-thorsten');
    });

    testWidgets('Probe: Ladezeichen beim Vorbereiten, Stopp beim Sprechen', (
      tester,
    ) async {
      final inner = FakeTextToSpeech(manual: true)..synthesis = Completer();
      final env = TestEnv()..sherpaTts = inner;
      env.speechModels.installed.add('tts-de-thorsten');
      await pumpScreen(tester, env, const VoiceVoicesScreen());
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(probe('de'));
      await tester.pump();
      // Preparing: spinner, no stop yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Probe beenden'), findsNothing);
      expect(find.byTooltip('Probe hören'), findsNothing);
      // Playing: stop button instead of the spinner.
      inner.synthesis!.complete();
      await settle(tester);
      expect(inner.state, TtsState.speaking);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Probe beenden'), findsOneWidget);
      await tester.tap(find.byTooltip('Probe beenden'));
      await settle(tester);
      expect(inner.stops, 1);
      expect(find.byTooltip('Probe hören'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Probe ohne Stopp: nach dem Ende wieder Abspielknopf', (
      tester,
    ) async {
      final env = TestEnv()..sherpaTts = FakeTextToSpeech(manual: true);
      env.speechModels.installed.add('tts-de-thorsten');
      await pumpScreen(tester, env, const VoiceVoicesScreen());
      await tester.tap(probe('de'));
      await settle(tester);
      env.sherpaTts.completeCurrent();
      await settle(tester);
      expect(find.byTooltip('Probe hören'), findsOneWidget);
    });

    testWidgets('fehlgeschlagene Probe zeigt eine kurze Meldung', (
      tester,
    ) async {
      final env = TestEnv();
      env.sherpaTts.nextError = StateError('kaputt');
      env.speechModels.installed.add('tts-de-thorsten');
      await pumpScreen(tester, env, const VoiceVoicesScreen());
      await tester.tap(probe('de'));
      await settle(tester);
      expect(
        find.text('Probe nicht möglich – die Stimme hat nicht gesprochen.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('Probe hören'), findsOneWidget);
    });

    testWidgets('Standardstimme nicht geladen: erste geladene wirkt, ohne '
        'Hinweis', (tester) async {
      final env = TestEnv();
      env.speechModels.installed.add('tts-de-kerstin');
      await pumpScreen(tester, env, const VoiceVoicesScreen());
      expect(checked(kerstin), isTrue);
      expect(checked(thorsten), isFalse);
      expect(find.byKey(const Key('hint-de')), findsNothing);
      await tester.tap(probe('de'));
      await settle(tester);
      expect(env.sherpaTts.calls.single.voice, 'tts-de-kerstin');
    });

    testWidgets('gewählte Stimme löschen entfernt die Wahl', (tester) async {
      final env = TestEnv();
      env.speechModels.installed.addAll(['tts-de-thorsten', 'tts-de-kerstin']);
      final c = await pumpScreen(tester, env, const VoiceVoicesScreen());
      await tester.tap(find.text(kerstin));
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.sherpaVoices, {
        'de': 'tts-de-kerstin',
      });
      await tester.tap(action(kerstin, 'Löschen'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Löschen'));
      await settle(tester);
      expect(c.read(voiceSettingsProvider).value!.sherpaVoices, isEmpty);
      expect(checked(thorsten), isTrue);
      expect(find.byKey(const Key('hint-de')), findsNothing);
    });

    testWidgets('Sprache-Seite führt zu „Stimmen“', (tester) async {
      final env = TestEnv();
      await pumpScreen(tester, env, const VoiceScreen());
      await tester.tap(find.text('Stimmen'));
      await settle(tester);
      expect(find.byType(VoiceVoicesScreen), findsOneWidget);
    });
  });

  group('VoiceSettings und Bausteine', () {
    test('JSON hin und zurück, ungültige Werte fallen auf Standard', () {
      const s = VoiceSettings(
        sttModel: 'whisper-small',
        sttLanguage: 'fr',
        tts: TtsPreference.system,
        ttsVoice: 'v',
        ttsRate: 1.5,
        minSpeechMs: 300,
        vadThreshold: 0.4,
      );
      expect(VoiceSettings.fromJson(s.toJson()), s);
      expect(s.toJson().containsKey('ttsVoice'), isTrue);
      expect(const VoiceSettings().toJson().containsKey('ttsVoice'), isFalse);
      expect(
        VoiceSettings.fromJson({
          'sttModel': 'evil',
          'sttLanguage': 'xx',
          'tts': 'loud',
          'ttsVoice': '',
          'ttsRate': 9,
          'minSpeechMs': 5,
          'vadThreshold': 1.5,
        }),
        const VoiceSettings(),
      );
      expect(s.hashCode, VoiceSettings.fromJson(s.toJson()).hashCode);
      expect(const VoiceSettings().effectiveLanguage('de'), 'de');
      expect(
        const VoiceSettings(sttLanguage: VoiceSettings.detect)
            .effectiveLanguage('de'),
        isNull,
      );
      expect(s.copyWith(clearVoice: true).ttsVoice, isNull);
      expect(s.copyWith(ttsRate: 1.0).ttsVoice, 'v');
      expect(() => voiceSettingsKey.decode('x'), throwsFormatException);
    });

    test('WP66: Offline-Stimmen je Sprache, Migration der alten Wahl', () {
      const s = VoiceSettings(
        sherpaVoices: {'de': 'tts-de-kerstin', 'fr': 'tts-fr-gilles'},
      );
      expect(VoiceSettings.fromJson(s.toJson()), s);
      expect(VoiceSettings.fromJson(s.toJson()).hashCode, s.hashCode);
      expect(s, isNot(const VoiceSettings()));
      expect(const VoiceSettings().toJson().containsKey('sherpaVoices'), false);
      expect(s.sherpaVoiceFor('de-DE'), 'tts-de-kerstin');
      expect(s.sherpaVoiceFor('en'), 'tts-en-ljspeech', reason: 'Standard');
      expect(s.sherpaVoiceFor('it'), isNull);
      expect(s.copyWith(sherpaVoices: {'en': 'tts-en-joe'}).sherpaVoices, {
        'en': 'tts-en-joe',
      });
      // Old settings: the one voice id was an offline voice -> its language.
      final old = VoiceSettings.fromJson({'ttsVoice': 'tts-fr-siwis'});
      expect(old.sherpaVoices, {'fr': 'tts-fr-siwis'});
      expect(old.ttsVoice, isNull);
      // A system voice stays where it was.
      final system = VoiceSettings.fromJson({'ttsVoice': 'de-de-x-abc'});
      expect(system.ttsVoice, 'de-de-x-abc');
      expect(system.sherpaVoices, isEmpty);
      // The new choice wins over the migrated one; invalid entries drop.
      final mixed = VoiceSettings.fromJson({
        'ttsVoice': 'tts-de-thorsten',
        'sherpaVoices': {
          'de': 'tts-de-kerstin',
          'fr': 'tts-de-kerstin', // wrong language
          'en': 'whisper-base', // not a voice
          'it': 'tts-it-x',
          'x': 5,
        },
      });
      expect(mixed.sherpaVoices, {'de': 'tts-de-kerstin'});
      expect(
        VoiceSettings.fromJson({'sherpaVoices': 'x'}).sherpaVoices,
        <String, String>{},
      );
    });

    test('ohne Modelle: Bausteine melden modelMissing', () async {
      final c = TestEnv().container();
      addTearDown(c.dispose);
      for (final p in [
        voiceActivityDetectorProvider.future,
        speechToTextProvider.future,
        voiceComponentsProvider.future,
      ]) {
        await expectLater(
          c.read(p),
          throwsA(
            isA<VoiceException>().having(
              (e) => e.kind,
              'kind',
              VoiceErrorKind.modelMissing,
            ),
          ),
        );
      }
      expect(c.read(audioInputProvider), isA<AudioInput>());
      final selection = await c.read(ttsSelectionProvider.future);
      expect(selection.engine, TtsEngine.system);
    });

    test('Statusmeldungen der Sprachausgabe', () {
      expect(
        ttsSelectionText(const TtsSelection(engine: TtsEngine.none, tts: null)),
        contains('nur auf dem Bildschirm'),
      );
      final fake = FakeTextToSpeech();
      expect(
        ttsSelectionText(
          TtsSelection(engine: TtsEngine.system, tts: fake, fallback: true),
        ),
        contains('Keine Offline-Stimme'),
      );
      expect(
        ttsSelectionText(
          TtsSelection(engine: TtsEngine.sherpa, tts: fake, fallback: true),
        ),
        contains('Keine Systemstimme installiert'),
      );
      expect(
        ttsSelectionText(TtsSelection(engine: TtsEngine.system, tts: fake)),
        'Wendelin spricht mit der Systemstimme.',
      );
    });

    test('ModelState', () {
      const a = ModelState(ModelPhase.downloading, progress: 0.5);
      expect(a.busy, isTrue);
      expect(a, const ModelState(ModelPhase.downloading, progress: 0.5));
      expect(a.hashCode, isNot(const ModelState(ModelPhase.absent).hashCode));
      expect(a.toString(), contains('downloading'));
      expect(const ModelState(ModelPhase.partial).busy, isFalse);
    });
  });
}
