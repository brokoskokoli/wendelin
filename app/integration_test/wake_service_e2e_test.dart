// Gerätetest WP50 a: Wake-Word-Dienst. Einlernen mit synthetischer Stimme
// „Hey Wendelin“ (AnnaHey_*, wie wake_enroll_e2e_test.dart, seit WP142), Dienst an (Bedingung „immer“), Speicher
// im Ruhezustand ohne Whisper, dann zehn Durchläufe: Bildschirm aus, die
// eingespeiste WAV („Wendelin“) öffnet das Overlay mit
// TriggerKind.wakeWord, Antwort im Overlay, BACK. Zuletzt der Speicher mit
// geladenem Whisper.
//
//   WENDELIN_MODELS=~/wendelin-models WAKE_LOG=<datei> \
//     tool/e2e_android.sh integration_test/wake_service_e2e_test.dart
//
// Das Skript führt `role` und `wake-loop` aus (Bildschirm, BACK, logcat).
//
// WP129: mit WENDELIN_WAKE_DETECTOR=model (auch templates, auto) wird vor dem
// Einschalten „Erkennung“ gesetzt; dann prüft der Lauf das trainierte Modell
// (Stufe 1 aus dem Klassifikator, `wake-cand ... detector=model`).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/main.dart' as app show assistantMain, wakeWordMain;
import 'package:wendelin/platform/secure_secret_store.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/routes.dart';
import 'package:wendelin/voice/wake/wake_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';
import 'support/wake_enroll_e2e.dart';

final class _SwitchableAudio implements AudioInput {
  AudioInput? inner;

  @override
  bool get isRunning => inner?.isRunning ?? false;

  @override
  Stream<Int16List> start() => inner!.start();

  @override
  Future<void> stop() async => inner?.stop();
}

Future<void> _until(Future<bool> Function() ok, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (!await ok()) {
    if (DateTime.now().isAfter(end)) fail('Zeitüberschreitung: $what');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

Future<String> _meminfo(Directory dir) async {
  final f = File('${dir.path}/meminfo.txt');
  if (f.existsSync()) f.deleteSync();
  await askHost('meminfo');
  await _until(() async => f.existsSync(), 'meminfo');
  return f.readAsStringSync().trim();
}

// The service and the overlay start their entry points in the root library,
// which is this test file.
@pragma('vm:entry-point')
Future<void> assistantMain() => app.assistantMain();

@pragma('vm:entry-point')
Future<void> wakeWordMain() => app.wakeWordMain();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (voiceE2e) await waitForDeviceFiles();
  });

  testWidgets(
    'Dienst: einlernen, an, zehn Treffer bei ausgeschaltetem Bildschirm',
    (tester) async {
      final dir = await e2eDirectory();
      final wavs = '${dir.path}/wake';
      final audio = _SwitchableAudio();
      final app = E2eApp(
        extraOverrides: [wakeAudioProvider.overrideWithValue(audio)],
      );
      await app.storage.settings.set(
        voiceSettingsKey,
        VoiceSettings(sttModel: 'whisper-base'),
      );
      final c = await app.pump(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      unawaited(nav.pushNamed(AppRoutes.wakeWord));
      await pumpUntil(tester, find.text('Aktivierungswort'));
      // Seit WP50b steht der Dienst oben, die Schaltfläche liegt weiter unten.
      await tester.scrollUntilVisible(
        find.text('Stimme einlernen'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(seconds: 1));
      audio.inner = WavAudioInput.sequence(annaHeyClips(wavs), speed: 4);
      await tester.tap(find.text('Stimme einlernen'));
      await pumpUntil(tester, find.text('Weiter'));
      await tester.enterText(find.byType(TextField), 'Anna');
      await tester.tap(find.text('Weiter'));
      await pumpUntil(
        tester,
        find.textContaining(RegExp(r'^(Mit \d+ Aufnahmen )?[Ss]peichern$')),
        timeout: const Duration(minutes: 3),
      );
      await tester.tap(
        find.textContaining(RegExp(r'^(Mit \d+ Aufnahmen )?[Ss]peichern$')),
      );
      await pumpUntil(tester, find.textContaining(RegExp(r'\d+ Aufnahmen')));
      final speakers = await c.read(wakeSpeakersProvider.future);
      expect(speakers, hasLength(1));
      // The service runs in another engine and reads the device's secret
      // store; the test app keeps its own: copy the voice over.
      final real = SecretWakeTemplateStore(SecureSecretStore());
      await real.saveSpeakers(speakers);
      await real.save(
        (await c.read(wakeTemplatesProvider(speakers.single.id).future))!,
      );

      // Bedingung „immer“ (der Emulator lädt nicht), Rolle, Dienst an.
      await askHost('role');
      final service = c.read(wakeServiceProvider.notifier);
      const detector = String.fromEnvironment('WENDELIN_WAKE_DETECTOR');
      if (detector.isNotEmpty) {
        await c
            .read(wakeDetectorProvider.notifier)
            .set(WakeDetectorChoice.parse(detector));
      }
      await service.setCondition(WakeCondition.always);
      expect(await service.setEnabled(enabled: true), isTrue);
      final platform = WakePlatform();
      await _until(() async => (await platform.status()).running, 'Dienst');
      // Ruhezustand: kein Whisper geladen, keine WAV.
      await Future<void>.delayed(const Duration(seconds: 20));
      // ignore: avoid_print
      print('WP50 meminfo Ruhe:\n${await _meminfo(dir)}');

      // WAV statt Mikrofon: Neustart des Dienstes liest wake.json.
      File('${dir.path}/wake-in.wav')
          .writeAsBytesSync(File('$wavs/test-solo.wav').readAsBytesSync());
      File('${dir.path}/wake.json')
          .writeAsStringSync('{"audio": "wake-in.wav", "leadingSilence": 14}');
      File(
        '${dir.path}/command.wav',
      ).writeAsBytesSync(File('${dir.path}/stt/de-05.wav').readAsBytesSync());
      File('${dir.path}/overlay.json').writeAsStringSync(
        '{"audio": "command.wav", "turns": [{"text": "Alles klar."}]}',
      );
      await service.setEnabled(enabled: false);
      await _until(() async => !(await platform.status()).running, 'Stopp');
      await service.setEnabled(enabled: true);
      await _until(() async => (await platform.status()).running, 'Neustart');

      // Zum Untersuchen von Hand: `run-as app.wendelin touch files/e2e/hold`
      // hält den Test an, bis die Datei gelöscht wird.
      final hold = File('${dir.path}/hold');
      while (hold.existsSync()) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      final result = File('${dir.path}/wake-result.txt');
      await askHost('wake-loop', timeout: const Duration(minutes: 25));
      await _until(() async => result.existsSync(), 'Ergebnis');
      final text = result.readAsStringSync().trim();
      // ignore: avoid_print
      print('WP50 Ergebnis: $text');
      // ignore: avoid_print
      print('WP50 meminfo nach den Treffern:\n${await _meminfo(dir)}');
      final m = RegExp(r'wakeWord=(\d+)/(\d+)').firstMatch(text)!;
      expect(m[1], m[2], reason: 'Stufe 1 muss jedes Mal treffen');
      // WENDELIN_KEEP: Dienst an lassen (Neustart-Prüfung, WP54).
      if (!const bool.fromEnvironment('WENDELIN_KEEP')) {
        await service.setEnabled(enabled: false);
      }
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
