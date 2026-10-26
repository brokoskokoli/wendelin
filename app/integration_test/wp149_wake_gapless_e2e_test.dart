// Gerätetest WP149: Übergabe vom Wake-Dienst an die App ohne Lücke, mit echtem
// Mikrofon (Dienst-AudioRecord und App-AudioRecord laufen gleichzeitig, das ist
// die Ursache des Fehlers). Den Treffer löst der Test selbst aus
// (`WakePlatform.debugHit`, nur Debug-Builds): das Skript `wake-loop`
// (WAKE_HIT=debug) schaltet den Bildschirm aus und legt `hit-request` ab, der
// Test sieht die Datei und ruft `debugHit`; das Overlay öffnet und nimmt mit
// dem Mikrofon auf. Das Skript wertet das Log aus und schreibt `gaps`,
// `gapMaxMs`, `silenceMaxMs`, `tailZeroMaxPct`, `conflicts`, `keeps` nach
// `wake-result.txt`.
//
//   WENDELIN_MODELS=~/wendelin-models WAKE_HIT=debug WAKE_LOG=<datei> \
//     tool/e2e_android.sh integration_test/wp149_wake_gapless_e2e_test.dart
//
// Erwartung je Lauf: `wake-conflict reason=recording handoff=kept action=keep`
// (Ursache belegt), `wake-gap` mit ms < 50 und silence=0, der Rest nicht stumm.

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
      await c
          .read(wakeDetectorProvider.notifier)
          .set(WakeDetectorChoice.parse('model'));
      // Kein wake.json/overlay.json (Reste eines Laufs): echtes Mikrofon.
      for (final f in ['wake.json', 'overlay.json']) {
        final file = File('${dir.path}/$f');
        if (file.existsSync()) file.deleteSync();
      }
      await service.setCondition(WakeCondition.always);
      expect(await service.setEnabled(enabled: true), isTrue);
      final platform = WakePlatform();
      final real0 = WendelinStorage(driftDatabase(name: 'wendelin'));
      await real0.settings.set(AppSettings.developerMode, true);
      await real0.close();
      await platform.setDevMode(enabled: true);
      await _until(() async => (await platform.status()).running, 'Dienst');
      // Ruhezustand: kein Whisper geladen.
      await Future<void>.delayed(const Duration(seconds: 20));

      // Das Skript legt je Durchlauf `hit-request` ab: dann löst der Dienst
      // einen Treffer aus (wie ein bestätigtes Weckwort, Vorlauf Stille).
      final request = File('${dir.path}/hit-request');
      var hits = 0;
      final poll = Timer.periodic(const Duration(milliseconds: 200), (_) async {
        if (!request.existsSync()) return;
        request.deleteSync();
        if (await platform.debugHit()) hits++;
      });
      addTearDown(poll.cancel);

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
      expect(hits, 10, reason: 'debugHit muss jedes Mal den Dienst treffen');
      expect(m[1], m[2], reason: 'Der Treffer öffnet jedes Mal das Overlay');
      // WP149: Übergabe ohne Lücke und ohne eingefügte Stille.
      final gaps = int.parse(RegExp(r'gaps=(\d+)').firstMatch(text)![1]!);
      final gapMax = int.parse(
        RegExp(r'gapMaxMs=(-?\d+)').firstMatch(text)![1]!,
      );
      final silenceMax = int.parse(
        RegExp(r'silenceMaxMs=(\d+)').firstMatch(text)![1]!,
      );
      int field(String name) =>
          int.parse(RegExp('$name=(\\d+)').firstMatch(text)![1]!);
      expect(gaps, greaterThan(0), reason: 'kein wake-gap im Log');
      // Ursache belegt: der Dienst sah die App-Aufnahme in der Überlappung
      // und behielt sein Mikrofon (sonst bleibt der Rest bei ~200 ms).
      expect(field('keeps'), greaterThan(0), reason: 'wake-conflict …keep');
      expect(field('conflicts'), field('keeps'), reason: 'nie close');
      // Der Rest darf nicht stumm sein, wenn das App-Mikrofon Signal hat
      // (Android schaltet eine Doppelaufnahme ggf. stumm): `silence=0` allein
      // beweist das nicht. Der Emulator-Ton ist unzuverlässig (beide Mikrofone
      // können nur Nullen liefern), daher Konsistenz statt Maximum: `tailMute`
      // zählt Durchläufe mit tailZero=100 bei App-Mikrofon mit Signal.
      expect(field('tailMute'), 0, reason: 'Rest stumm, App-Mikrofon nicht');
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
