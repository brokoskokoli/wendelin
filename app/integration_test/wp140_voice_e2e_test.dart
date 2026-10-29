// E2E WP140: Szenario 2 (Gesprächsmodus, echtes leises Rauschen `noise2` im
// Folgefenster ruft das Modell nicht auf) und Szenario 3 (strenge
// Bestätigung: „Ja“ bestätigt, „Okay“, „All right“, „Sure“ bei Deutsch nicht).
// „Yeah“ ist nicht prüfbar: Whisper macht daraus „Ja“. Die WAVs (noise2.wav,
// okay.wav, allright.wav, sure.wav) liegen in <WENDELIN_MODELS>/wake-e2e/ und
// damit unter files/e2e/wake/.
//
//   WENDELIN_MODELS=~/wendelin-models \
//     tool/e2e_android.sh integration_test/wp140_voice_e2e_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/main.dart' as app show assistantMain, openAppStorage;
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

@pragma('vm:entry-point')
Future<void> assistantMain() => app.assistantMain();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PickedVault vault;
  late SafVaultPort port;
  late Directory e2e;
  final lines = <String>[];

  setUpAll(() async {
    if (!voiceE2e) return;
    await waitForDeviceFiles();
    vault = await pickTestVault();
    port = vaultPort(vault);
    e2e = await e2eDirectory();
    voiceLogSink = (l) {
      lines.add(l);
      debugPrint(l);
    };
  });
  tearDownAll(() async {
    if (!voiceE2e) return;
    final spec = File('${e2e.path}/overlay.json');
    if (spec.existsSync()) spec.deleteSync();
    if (await port.exists(testDailyNote)) await port.delete(testDailyNote);
    await const VaultAccess().release(vault.uri);
  });

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

  for (final noise in ['noise2']) {
    testWidgets(
      'S2 $noise: leise Störung im Folgefenster ruft das Modell nicht auf',
      (tester) async {
        final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
        await setup.settings.set(AppSettings.setupWizardDone, true);
        await setup.settings.set(
          voiceSettingsKey,
          const VoiceSettings(sttModel: 'whisper-base', conversationMode: true),
        );
        await setup.close();
        File(await fixtureWav('lock-02')).copySync('${e2e.path}/lock-02.wav');
        File('${e2e.path}/wake/$noise.wav').copySync('${e2e.path}/$noise.wav');
        File('${e2e.path}/overlay.json').writeAsStringSync(
          jsonEncode({
            'audio': ['lock-02.wav', '$noise.wav'],
            'turns': [
              {'text': 'ANTWORT-EINS'},
              {'text': 'ANTWORT-ZWEI'},
            ],
          }),
        );
        await askHost('assist');
        final end = DateTime.now().add(const Duration(minutes: 2));
        var texts = '';
        while (!texts.contains('ANTWORT-EINS')) {
          if (DateTime.now().isAfter(end)) fail('erste Antwort fehlt:\n$texts');
          await Future<void>.delayed(const Duration(seconds: 3));
          texts = await history();
        }
        // Folgefenster mit leiser Störung abwarten.
        await Future<void>.delayed(const Duration(seconds: 45));
        texts = await history();
        debugPrint(
          'WP30-WP140-S2 $noise Antwort1=${texts.contains('ANTWORT-EINS')} '
          'Antwort2=${texts.contains('ANTWORT-ZWEI')}',
        );
        expect(texts, contains('ANTWORT-EINS'));
        expect(texts, isNot(contains('ANTWORT-ZWEI')));
        await askHost('back');
      },
      skip: !voiceE2e,
      timeout: const Timeout(Duration(minutes: 6)),
    );
  }

  /// D3 by voice: request (de-05), then the answer WAV at [answerPath].
  Future<String> d3(WidgetTester tester, String answerPath) async {
    await resetTestNote(port);
    final audio = WavAudioInput.files([await fixtureWav('de-05'), answerPath]);
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        ToolCallBlock(
          id: 'r1',
          name: 'obsidian__replace_section',
          argumentsJson: jsonEncode({
            'path': testDailyNote,
            'heading': 'Ideen',
            'content': '- Wendelin getestet',
          }),
        ),
      ]),
      ScriptedTurn.text('Fertig.'),
    ]);
    final e2eApp = E2eApp(
      startup: StartupSettings(
        enabledIntegrations: const {'obsidian'},
        obsidian: testObsidian(vault),
      ),
      config: (_) => deviceTestProviderConfig(provider),
      extraOverrides: [audioInputProvider.overrideWithValue(audio)],
    );
    await e2eApp.storage.settings.set(
      voiceSettingsKey,
      const VoiceSettings(sttModel: 'whisper-base'),
    );
    final c = await e2eApp.pump(tester);
    await pumpUntil(
      tester,
      find.byWidgetPredicate((w) => w is MicButton && w.state == MicState.idle),
    );
    final stt = await c.read(speechToTextProvider.future);
    final heard = await tester.runAsync(
      () => stt.transcribe(Wav.read(answerPath).samples, language: 'de'),
    );
    final t = heard!.text.toLowerCase().replaceAll(RegExp('[^a-zäöüß ]'), '');
    debugPrint(
      'WP30-WP140-S3 stt ${p(answerPath)} words=${t.trim().split(' ').length} '
      'isJa=${t.trim() == 'ja'} '
      'conf=${heard.confidence}',
    );
    final before = lines.length;
    await tester.tap(find.byType(MicButton));
    final end = DateTime.now().add(const Duration(seconds: 120));
    bool settled() {
      final phase = c.read(agentControllerProvider).tool('r1')?.phase;
      return phase == ToolPhase.done ||
          phase == ToolPhase.declined ||
          c.read(voiceControllerProvider).tapOnly;
    }

    while (!settled()) {
      if (DateTime.now().isAfter(end)) fail('D3: weder Antwort noch Tipp');
      await tester.pump(const Duration(milliseconds: 200));
    }
    final tap = c.read(voiceControllerProvider).tapOnly;
    if (tap) c.read(agentControllerProvider.notifier).answer(approved: false);
    await waitIdle(tester);
    final mine = lines.skip(before).toList();
    final exit = mine.lastWhere(
      (l) => l.contains(' confirm-exit '),
      orElse: () => 'none',
    );
    debugPrint(
      'WP30-WP140-S3 ${p(answerPath)} tapOnly=$tap '
      'unclear=${mine.where((l) => l.contains('confirm-unclear')).length} '
      '${RegExp(r'reason=(\S+)').firstMatch(exit)?[1]}',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    return exit;
  }

  testWidgets(
    'S3: strenge Bestätigung, Ja bestätigt, Okay/All right/Sure bei Deutsch nicht',
    (tester) async {
      final ja = await d3(tester, await fixtureWav('de-11'));
      expect(ja, contains('answered(yes)'));
      for (final w in ['okay', 'allright', 'sure']) {
        final exit = await d3(tester, '${e2e.path}/wake/$w.wav');
        expect(exit, isNot(contains('answered(yes)')), reason: w);
      }
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

String p(String path) => path.split('/').last;
