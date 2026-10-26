// Gerätetest WP149: Übergabe vom Wake-Dienst an die App ohne Lücke. Wie
// wake_service_e2e_test.dart (Dienst an, Bildschirm aus, eingespeiste WAV
// öffnet das Overlay, zehn Durchläufe), prüft zusätzlich die Übergabe aus dem
// Log: `wake-gap ms` < 50 und `silence=0` in jedem Durchlauf (das Skript
// `wake-loop` schreibt `gaps`, `gapMaxMs`, `silenceMaxMs` ins Ergebnis).
//
//   WENDELIN_MODELS=~/wendelin-models WAKE_LOG=<datei> \
//     tool/e2e_android.sh integration_test/wp149_wake_gapless_e2e_test.dart
//
// Hinweis: Der Dienst liest hier eine WAV statt des Mikrofons; die Ursache
// (App-AudioRecord als fremde Aufnahme, `wake-conflict reason=recording`)
// tritt nur mit echtem Dienst-Mikrofon auf und ist am Handy zu prüfen
// (docs/testing/m5/wp149.md). Der Lauf schützt die Übergabe-Logik und die
// Messung.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/di/wake_service.dart';
import 'package:wendelin/main.dart' as app show assistantMain, wakeWordMain;
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

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
    'Wake-Übergabe: zehn Treffer ohne Lücke (wake-gap < 50 ms, silence=0)',
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
      // Bedingung „immer“ (der Emulator lädt nicht), Rolle, Dienst an.
      await askHost('role');
      final service = c.read(wakeServiceProvider.notifier);
      const detector = 'model';
      if (detector.isNotEmpty) {
        await c
            .read(wakeDetectorProvider.notifier)
            .set(WakeDetectorChoice.parse(detector));
      }
      await service.setCondition(WakeCondition.always);
      expect(await service.setEnabled(enabled: true), isTrue);
      final platform = WakePlatform();
      final real0 = WendelinStorage(driftDatabase(name: 'wendelin'));
      await real0.settings.set(AppSettings.developerMode, true);
      await real0.close();
      await platform.setDevMode(enabled: true);
      await _until(() async => (await platform.status()).running, 'Dienst');
      // Ruhezustand: kein Whisper geladen, keine WAV.
      await Future<void>.delayed(const Duration(seconds: 20));

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
      final m = RegExp(r'wakeWord=(\d+)/(\d+)').firstMatch(text)!;
      expect(m[1], m[2], reason: 'Stufe 1 muss jedes Mal treffen');
      // WP149: Übergabe ohne Lücke und ohne eingefügte Stille.
      final gaps = int.parse(RegExp(r'gaps=(\d+)').firstMatch(text)![1]!);
      final gapMax = int.parse(
        RegExp(r'gapMaxMs=(-?\d+)').firstMatch(text)![1]!,
      );
      final silenceMax = int.parse(
        RegExp(r'silenceMaxMs=(\d+)').firstMatch(text)![1]!,
      );
      expect(gaps, greaterThan(0), reason: 'kein wake-gap im Log');
      expect(gapMax, lessThan(50), reason: 'Lücke der Übergabe in ms');
      expect(silenceMax, 0, reason: 'keine Stillefüllung (Notfall)');
      // WENDELIN_KEEP: Dienst an lassen (Neustart-Prüfung, WP54).
      if (!const bool.fromEnvironment('WENDELIN_KEEP')) {
        await service.setEnabled(enabled: false);
      }
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 40)),
  );
}
