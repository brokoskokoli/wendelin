// Gerätetest WP54: Gesprächsmodus im Overlay. Das Overlay hört nacheinander
// drei WAVs (Frage, Folgefrage im Folgefenster, gesprochenes Stoppwort („Halt.“)). Der
// Skript-Provider hätte drei Antworten; nach dem Stoppwort darf die dritte nie
// fallen und die Sitzung endet. Kein Live-Modell. Liegt alphabetisch hinter
// den Tests, die einen leeren Audit-Log/Verlauf erwarten (Sammellauf).
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/voice_conversation_e2e_test.dart

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
    'Gesprächsmodus: Folgefrage im Folgefenster, Stoppwort beendet',
    (tester) async {
      await waitForDeviceFiles();
      final e2e = await e2eDirectory();
      addTearDown(() async {
        final spec = File('${e2e.path}/overlay.json');
        if (spec.existsSync()) spec.deleteSync();
      });

      final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
      await setup.settings.set(AppSettings.onboardingDone, true);
      await setup.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-base', conversationMode: true),
      );
      await setup.close();

      const wavs = ['lock-02', 'de-06', 'stop-01'];
      for (final w in wavs) {
        File(await fixtureWav(w)).copySync('${e2e.path}/$w.wav');
      }
      File('${e2e.path}/overlay.json').writeAsStringSync(
        jsonEncode({
          'audio': [for (final w in wavs) '$w.wav'],
          'turns': [
            {'text': 'ANTWORT-EINS'},
            {'text': 'ANTWORT-ZWEI'},
            {'text': 'ANTWORT-DREI'},
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

      final end = DateTime.now().add(const Duration(minutes: 3));
      var texts = '';
      while (!texts.contains('ANTWORT-ZWEI')) {
        if (DateTime.now().isAfter(end)) {
          fail('Folgefrage nicht beantwortet:\n$texts');
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        texts = await history();
      }
      // Zeit für das Stoppwort (dritte WAV) und das Ende der Sitzung.
      await Future<void>.delayed(const Duration(seconds: 40));
      texts = await history();
      expect(texts, contains('ANTWORT-EINS'));
      expect(
        texts,
        isNot(contains('ANTWORT-DREI')),
        reason: 'Stoppwort endet\n$texts',
      );
      await askHost('back');
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
