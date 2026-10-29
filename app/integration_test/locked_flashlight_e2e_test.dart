// Gerätetest WP53 (K16): Gesperrtes Gerät, Taschenlampe ohne Entsperren.
// Das Skript setzt auf dem Emulator eine PIN (`locksettings set-pin`),
// schaltet den Bildschirm aus und an und öffnet das Overlay mit
// KEYCODE_ASSIST. Das Overlay hört eine WAV (Whisper base), die
// Taschenlampe ist ein Datei-Port (`torch: file`, der Emulator hat keine
// LED). Runde 1: „Taschenlampe an“ → Port meldet an, Audit mit
// `whileLocked`, kein Modellaufruf. Runde 2: „Wie spät ist es?“ → keine
// Aktion, Audit `refused` ohne Text, kein Modellaufruf. Danach entsperrt
// das Skript wieder und entfernt die PIN (auch beim Aufräumen).
//
// Nur mit `WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/locked_flashlight_e2e_test.dart` auf einem Emulator.

import 'dart:convert';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show assistantMain, openAppStorage;
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/voice_e2e.dart';

/// The overlay's Dart entrypoint (see `overlay_e2e_test.dart`).
@pragma('vm:entry-point')
Future<void> assistantMain() => app.assistantMain();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'gesperrt: „Taschenlampe an“ geht, „Wie spät ist es?“ wird abgewiesen',
    (tester) async {
      await waitForDeviceFiles();
      final e2e = await e2eDirectory();
      final torchState = File('${e2e.path}/torch-state');
      addTearDown(() async {
        for (final f in ['overlay.json', 'torch-state']) {
          final file = File('${e2e.path}/$f');
          if (file.existsSync()) file.deleteSync();
        }
        await askHost('unlock');
      });

      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.setupWizardDone, true);
      await setup.settings.set(
        AppSettings.integrationEnabled('flashlight'),
        true,
      );
      await setup.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base'),
      );
      await setup.close();

      Future<void> writeSpec(String wav) async {
        File(await fixtureWav(wav)).copySync('${e2e.path}/$wav.wav');
        File('${e2e.path}/overlay.json').writeAsStringSync(
          jsonEncode({
            'audio': '$wav.wav',
            'torch': 'file',
            // Käme ein Modellaufruf, stünde diese Antwort im Verlauf.
            'turns': [
              {'text': 'MODELL-WURDE-AUFGERUFEN'},
            ],
          }),
        );
      }

      // Runde 1: Taschenlampe an.
      await writeSpec('lock-01');
      await askHost('assist-locked');
      final end = DateTime.now().add(const Duration(seconds: 90));
      while (!(torchState.existsSync() &&
          torchState.readAsStringSync() == 'on')) {
        if (DateTime.now().isAfter(end)) fail('Taschenlampe nicht angegangen');
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await askHost('back');

      // Runde 2: etwas anderes.
      torchState.writeAsStringSync('off');
      await writeSpec('lock-02');
      await askHost('assist-locked');
      await Future<void>.delayed(const Duration(seconds: 25));
      expect(torchState.readAsStringSync(), 'off', reason: 'keine Aktion');
      await askHost('back');
      await askHost('unlock');

      final (storage, _) = await app.openAppStorage();
      addTearDown(storage.close);
      final audit = [
        for (final e in await storage.audit.query()) (e.kind, e.payload),
      ];
      final tools = audit.where((a) => a.$1 == AuditKind.toolCall).toList();
      expect(tools, hasLength(1));
      expect(tools.single.$2['tool'], 'flashlight__on');
      expect(tools.single.$2['whileLocked'], isTrue);
      final requests = audit.where((a) => a.$1 == AuditKind.request).toList();
      expect(requests, hasLength(1));
      expect(requests.single.$2['refused'], isTrue);
      expect(requests.single.$2.containsKey('text'), isFalse);
      for (final a in audit) {
        expect(a.$1, isNot(AuditKind.routing), reason: 'kein Modellaufruf');
        expect(a.$1, isNot(AuditKind.usage), reason: 'kein Modellaufruf');
      }
      final sessions = await storage.conversations.sessions(limit: 5);
      expect(sessions, isEmpty, reason: 'kein Verlauf');

      // Runde 3 (WP114, K85): gesperrt gefragt, entsperrt: das Overlay bleibt
      // offen und die Anfrage von vorher wird beantwortet (Verlauf entsteht
      // erst jetzt). Log: kein `conv-exit reason=tap` nach dem Entsperren.
      File('${e2e.path}/overlay.json').writeAsStringSync(
        jsonEncode({
          'audio': 'lock-02.wav',
          'torch': 'file',
          'turns': [
            {'text': 'Es ist zehn Uhr.'},
          ],
        }),
      );
      await askHost('assist-locked');
      await Future<void>.delayed(const Duration(seconds: 25));
      await askHost('unlock');
      final answered = DateTime.now().add(const Duration(seconds: 90));
      while ((await storage.conversations.sessions(limit: 5)).isEmpty) {
        if (DateTime.now().isAfter(answered)) {
          fail('Anfrage lief nach dem Entsperren nicht weiter');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
