// Live-Gerätetest M2 (WP19, manuell, kostet Bruchteile eines Cents): ein
// gesprochener Satz aus einer WAV („Ergänze in meiner Tagesnotiz, dass ich
// den Zahnarzt angerufen habe.“) → Whisper small (feste Sprache) → Claude
// Haiku → Tagesnotiz im SAF-Test-Vault ergänzt, danach Rückgängig.
//
// Nur mit `WENDELIN_LIVE=1 WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/voice_live_e2e_test.dart` und gesetztem
// ANTHROPIC_API_KEY (siehe live_e2e_test.dart: der Key geht per `run-as`
// in die App-Daten und wird sofort gelöscht).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

const _live = bool.fromEnvironment('WENDELIN_LIVE');
const _model = 'claude-haiku-5-5';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Live: gesprochene Bitte → Whisper small → Claude Haiku → Tagesnotiz',
    (tester) async {
      await waitForDeviceFiles();
      final key = await takeLiveKey();
      expect(key, isNotEmpty);
      final vault = await pickTestVault();
      final port = vaultPort(vault);
      // Die Tagesnotiz von heute (das Modell nennt kein Datum).
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final today = 'Tagebuch/${now.year}-${two(now.month)}-${two(now.day)}.md';
      if (await port.exists(today)) {
        await port.write(today, testNoteBefore);
      } else {
        await port.create(today, testNoteBefore);
      }
      addTearDown(() async {
        if (await port.exists(today)) await port.delete(today);
        await const VaultAccess().release(vault.uri);
      });

      final adapter = AnthropicMessagesAdapter(
        credentials: Credentials.apiKey(key, style: ApiKeyStyle.xApiKey),
        defaultModel: _model,
        options: const AnthropicOptions(reasoningEffort: 'low'),
      );
      final audio = WavAudioInput.file(await fixtureWav('de-05'));
      final app = E2eApp(
        startup: StartupSettings(
          enabledIntegrations: const {'obsidian'},
          obsidian: testObsidian(vault),
        ),
        config: (_) => ProviderConfig(
          primary: ProviderTarget(
            profileId: 'claude',
            modelId: _model,
            provider: adapter,
            privacy: PrivacyLevel.standard,
          ),
          names: const {'claude': 'Claude Haiku'},
        ),
        extraOverrides: [audioInputProvider.overrideWithValue(audio)],
      );
      await app.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-small'),
      );
      final c = await app.pump(tester);
      // Kosten auch bei einem Fehlschlag ausgeben (Audit-Log „usage“).
      addTearDown(() async {
        final audit = await auditText(app);
        for (final l in audit.split('\n').where((l) => l.startsWith('usage'))) {
          // ignore: avoid_print
          print('M2-Live $l');
        }
      });
      await pumpUntil(
        tester,
        find.byWidgetPredicate(
          (w) => w is MicButton && w.state == MicState.idle,
        ),
      );
      final watch = Stopwatch()..start();
      await tester.tap(find.byType(MicButton));
      await pumpUntil(
        tester,
        find.textContaining('Rückgängig · '),
        timeout: const Duration(seconds: 120),
      );
      watch.stop();
      final note = await port.read(today);
      // ignore: avoid_print
      print('M2-Live Notiz danach: ${note.replaceAll('\r\n', '⏎')}');
      expect(note.toLowerCase(), contains('zahnarzt'));
      // Wo das Modell anhängt (Ende oder unter „Log“), entscheidet es; der
      // alte Inhalt bleibt Zeile für Zeile in derselben Reihenfolge, die
      // neuen Zeilen enden wie die Datei mit CRLF.
      final before = testNoteBefore.split('\r\n');
      final after = note.split('\r\n');
      expect(after.length, greaterThan(before.length));
      var i = 0;
      for (final line in after) {
        if (i < before.length && line == before[i]) i++;
      }
      expect(
        i,
        before.length,
        reason: 'alter Inhalt vollständig, in Reihenfolge',
      );
      expect(
        RegExp(r'(?<!\r)\n').hasMatch(note),
        isFalse,
        reason: 'neue Zeilen mit CRLF wie die Datei',
      );
      final stt = await c.read(speechToTextProvider.future);
      final timing = (stt as WhisperSpeechToText).lastTiming!;

      await tester.tap(find.textContaining('Rückgängig · '));
      await pumpUntil(tester, find.text('Rückgängig gemacht'));
      expect(await port.read(today), testNoteBefore);
      await waitIdle(tester);

      expect(await auditText(app), contains('obsidian__append_daily_note'));
      // ignore: avoid_print
      print(
        'M2-Live: ${watch.elapsedMilliseconds} ms Tipp bis Ergebnis; $timing',
      );
    },
    skip: !(_live && voiceE2e),
  );
}
