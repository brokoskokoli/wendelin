// Gerätetest WP64: Gesprächsmodus mit AKTIVEM Barge-in-Zuhörer. Lernt die
// Stimme Anna ein (WAVs, echte Merkmalskette), kopiert die Vorlagen in den
// echten Secret-Store (das Overlay läuft in einer anderen Engine) und lässt
// das Overlay hören: Frage, während der langen Antwort „Wendelin“ (Barge-in),
// danach eine Folgefrage. Prüft den Verlauf; das Mikrofon-Log
// (`Wendelin/voice barge-listen on=true`, `barge-hit`) prüft der Aufrufer
// per logcat.
//
// WP113 (K84): „Stopp“ wirkt jetzt zweistufig. Das Mikrofon-Log muss
// `barge-config verify=true`, `barge-cand kind=…` und `barge-verify
// result=stop`, danach `barge-hit kind=keyword-stop` zeigen (ohne
// `barge-verify` kein Treffer); das prüft der E2E-Agent per logcat
// (`docs/testing/m5/wp113.md`).
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/voice_barge_in_e2e_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/bootstrap/run_app.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/main.dart' as app show openAppStorage;
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_enroller.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/testing.dart' show FakeTextToSpeech;
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/barge_log.dart';
import 'support/e2e.dart';
import 'support/voice_e2e.dart';

/// The overlay's entry point: as `assistantMain`, but with a fake voice that
/// "speaks" four seconds per sentence (the AOSP emulator has no system TTS
/// and no offline voice, so the pipeline would never reach `speaking`).
@pragma('vm:entry-point')
Future<void> assistantMain() async {
  voiceLogEngine = 'overlay';
  WidgetsFlutterBinding.ensureInitialized();
  // Die Diagnosezeilen auch in eine Datei, damit der Test sie prüft
  // (logcat gehört dem Aufrufer, `barge_log.dart`).
  final log = File('${(await e2eDirectory()).path}/voice.log');
  voiceLogSink = (l) {
    debugPrint(l);
    log.writeAsStringSync('$l\n', mode: FileMode.append);
  };
  final (storage, startup) = await app.openAppStorage();
  await runWendelinApp(
    storage,
    startup,
    const AssistantOverlayApp(),
    extra: [
      ...await deviceTestOverrides(),
      systemTtsProvider.overrideWithValue(
        FakeTextToSpeech(utteranceDuration: const Duration(seconds: 4)),
      ),
    ],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Gesprächsmodus: „Stopp“ allein unterbricht die Ausgabe und schließt das Overlay',
    (tester) async {
      await waitForDeviceFiles();
      final e2e = await e2eDirectory();
      final wavs = '${e2e.path}/wake';
      final voiceLogFile = File('${e2e.path}/voice.log');
      if (voiceLogFile.existsSync()) voiceLogFile.deleteSync();
      addTearDown(() async {
        final spec = File('${e2e.path}/overlay.json');
        if (spec.existsSync()) spec.deleteSync();
      });

      // Einlernen (ohne Oberfläche) in den echten Secret-Store.
      final host = E2eApp();
      final c = await host.pump(tester);
      final real = SecretWakeTemplateStore(SecureSecretStore());
      final enroller = WakeEnroller(
        audio: WavAudioInput.sequence([
          for (var i = 1; i <= 15; i++)
            WavAudioInput.file('$wavs/Anna_${i.toString().padLeft(2, '0')}.wav')
                .samples,
        ], speed: 4),
        features: c.read(wakeFeaturesFactoryProvider)(),
        store: real,
        speakerId: 'anna',
        pause: Duration.zero,
      );
      await enroller.run();
      expect(enroller.error, isNull);
      await enroller.finish();
      await real.saveSpeakers(const [WakeSpeaker(id: 'anna', name: 'Anna')]);
      // ignore: avoid_print
      print('WP64 eingelernt: ${enroller.accepted} Aufnahmen');

      final stopEnroller = WakeEnroller(
        audio: WavAudioInput.sequence([
          for (var i = 1; i <= 12; i++)
            WavAudioInput.file('$wavs/Stop_${i.toString().padLeft(2, '0')}.wav')
                .samples,
        ], speed: 4),
        features: c.read(wakeFeaturesFactoryProvider)(),
        store: real.stop,
        speakerId: 'anna',
        target: 10,
        minimum: 6,
        threshold: stopProvisionalThreshold,
        pause: Duration.zero,
      );
      await stopEnroller.run();
      expect(stopEnroller.error, isNull);
      await stopEnroller.finish();
      // ignore: avoid_print
      print('WP64b Stopp eingelernt: ${stopEnroller.accepted} Aufnahmen');

      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.onboardingDone, true);
      await setup.settings.set(
        voiceSettingsKey,
        const VoiceSettings(
          sttModel: 'whisper-base',
          conversationMode: true,
          bargeIn: BargeInMode.keywords,
        ),
      );
      await setup.close();

      // 1,5 s Vorlauf: das erste Fenster der Merkmalskette braucht 2 s Audio.
      final solo = Wav.read('$wavs/test-stop.wav').samples;
      final padded = Int16List(24000 + solo.length + 16000)
        ..setRange(24000, 24000 + solo.length, solo);
      File('${e2e.path}/barge.wav').writeAsBytesSync(Wav(padded).encode());
      for (final w in ['lock-02']) {
        File(await fixtureWav(w)).copySync('${e2e.path}/$w.wav');
      }
      final long = List.filled(30, 'langer Satz zum Unterbrechen').join('. ');
      File('${e2e.path}/overlay.json').writeAsStringSync(
        jsonEncode({
          'audio': ['lock-02.wav', 'barge.wav'],
          'turns': [
            {'text': 'ANTWORT-EINS $long'},
            {'text': 'ANTWORT-ZWEI'},
          ],
        }),
      );

      await askHost('assist');
      Future<String> history() async {
        final (storage, _) = await app.openAppStorage();
        try {
          final sessions = await storage.conversations.sessions(limit: 5);
          return [
            for (final s in sessions)
              for (final m in await storage.conversations.messages(s.id))
                jsonEncode(m.message.content.map((b) => '$b').toList()),
          ].join('\n');
        } finally {
          await storage.close();
        }
      }

      // Nach „Stopp“ allein: Ausgabe weg, Sitzung beendet, keine Folgeantwort.
      await Future<void>.delayed(const Duration(seconds: 75));
      final texts = await history();
      // ignore: avoid_print
      print('WP64b Verlauf:\n$texts');
      expect(texts, contains('ANTWORT-EINS'));
      expect(texts, isNot(contains('ANTWORT-ZWEI')));
      // WP113 (K84): Kandidat -> Gegenprüfung -> Treffer, nie ein Treffer
      // nach `no`/`echo`/`skip`.
      final lines = voiceLogFile.readAsLinesSync();
      expect(
        bargeLogProblem(lines, hitKind: 'keyword-stop'),
        isNull,
        reason: lines.where((l) => l.contains('barge-')).join('\n'),
      );
      expect(
        lines.where((l) => logField(l, 'kind') == 'keyword-wake'),
        isEmpty,
        reason: 'Stopp darf nie als Wake gewertet werden (T20-B.1)',
      );
      await askHost('back');
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
