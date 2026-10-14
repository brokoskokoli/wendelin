// Gerätetest WP30 (Befunde B7, B11, B14 aus dem Gerätetest 2026-10-13).
//
// B7: D3-Ablauf per Stimme. Die WAV-Einspeisung liefert erst die Bitte,
//     nach der gesprochenen Frage die Antwort („Nein“ bzw. „Ja“). Jeder
//     Durchlauf muss zuhören (Antwort wirkt) oder „Antworte per Tipp“
//     zeigen, mit genau einer `confirm-exit`-Zeile. Abwechselnd mit
//     vorheriger Overlay-Nutzung im selben Prozess (KEYCODE_ASSIST).
//     Anzahl der Runden: `--dart-define=WENDELIN_REPEAT=<n>` (Standard 1,
//     also 2 Durchläufe; Messkriterium: 10 Runden = 20 Durchläufe).
// B11: `mic-ready after=` des ersten Tipps nach dem Start (Hauptbildschirm).
// B14: whisper-small, App und Overlay je einmal genutzt: `dumpsys meminfo`
//      (TOTAL PSS) und höchstens ein `model-load whisper-small`.
//
// Nur mit `WENDELIN_MODELS=<dir> tool/e2e_android.sh
// integration_test/voice_robustness_e2e_test.dart` (instrumentiert, weil das
// Overlay seine eigene Engine startet).

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
import 'package:wendelin/main.dart' as app show assistantMain;
import 'package:wendelin/platform/saf_vault_port.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/e2e.dart';
import 'support/voice_e2e.dart';

/// The overlay's Dart entrypoint in this test build (see
/// `overlay_e2e_test.dart`).
@pragma('vm:entry-point')
Future<void> assistantMain() => app.assistantMain();

const _rounds = int.fromEnvironment('WENDELIN_REPEAT', defaultValue: 1);

/// What the scripted provider replaces (D3: a section of a known note).
Map<String, Object?> _replaceArgs() => {
  'path': testDailyNote,
  'heading': 'Ideen',
  'content': '- Wendelin getestet',
};

/// Settings the overlay engine reads from the app database.
Future<void> _overlaySettings(String model) async {
  final setup = WendelinStorage(driftDatabase(name: 'wendelin'));
  await setup.settings.set(AppSettings.onboardingDone, true);
  await setup.settings.set(voiceSettingsKey, VoiceSettings(sttModel: model));
  await setup.close();
}

/// Uses the overlay once: KEYCODE_ASSIST, it hears a question (WAV) and
/// answers with text, then it is closed (Zurück).
Future<void> _useOverlay(Directory e2e) async {
  File(await fixtureWav('de-02')).copySync('${e2e.path}/de-02.wav');
  File('${e2e.path}/overlay.json').writeAsStringSync(
    jsonEncode({
      'audio': ['de-02.wav'],
      'turns': [
        {'text': 'Sonnig.'},
      ],
    }),
  );
  await askHost('assist');
  // Listening, Whisper and the answer take a few seconds in the overlay.
  await Future<void>.delayed(const Duration(seconds: 12));
  await askHost('back');
  await Future<void>.delayed(const Duration(seconds: 2));
}

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
    for (final f in ['overlay.json', 'de-02.wav']) {
      final file = File('${e2e.path}/$f');
      if (file.existsSync()) file.deleteSync();
    }
    if (await port.exists(testDailyNote)) await port.delete(testDailyNote);
    await const VaultAccess().release(vault.uri);
  });

  /// One D3 by voice in a fresh app (same process): the request, the
  /// question, then [answer] (`ja`/`nein`). Returns the exit line.
  Future<String> d3(WidgetTester tester, String model, String answer) async {
    await resetTestNote(port);
    final audio = WavAudioInput.files([
      await fixtureWav('de-05'),
      await fixtureWav(answer == 'ja' ? 'de-11' : 'de-12'),
    ]);
    final provider = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        ToolCallBlock(
          id: 'r1',
          name: 'obsidian__replace_section',
          argumentsJson: jsonEncode(_replaceArgs()),
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
      VoiceSettings(sttModel: model),
    );
    final c = await e2eApp.pump(tester);
    await pumpUntil(
      tester,
      find.byWidgetPredicate((w) => w is MicButton && w.state == MicState.idle),
    );
    final exitsBefore = lines.where((l) => l.contains(' confirm-exit ')).length;
    await tester.tap(find.byType(MicButton));
    final end = DateTime.now().add(const Duration(seconds: 120));
    bool settled() {
      final phase = c.read(agentControllerProvider).tool('r1')?.phase;
      return phase == ToolPhase.done ||
          phase == ToolPhase.declined ||
          c.read(voiceControllerProvider).tapOnly;
    }

    while (!settled()) {
      if (DateTime.now().isAfter(end)) {
        fail('D3 ($model, $answer): weder Antwort noch „Antworte per Tipp“');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (c.read(voiceControllerProvider).tapOnly) {
      expect(find.text('Antworte per Tipp'), findsOneWidget);
      c.read(agentControllerProvider.notifier).answer(approved: false);
    }
    await waitIdle(tester);
    final exits = lines
        .where((l) => l.contains(' confirm-exit '))
        .skip(exitsBefore)
        .toList();
    expect(exits, hasLength(1), reason: 'genau eine Ausstiegszeile');
    final exit = exits.single;
    if (exit.contains('reason=answered(yes)')) {
      expect(await port.read(testDailyNote), isNot(testNoteBefore));
    } else {
      expect(await port.read(testDailyNote), testNoteBefore);
    }
    // Ends the app engine's providers (frees its Whisper).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    return exit;
  }

  testWidgets(
    'B7: Ja/Nein per Stimme nach der Frage, mit und ohne Overlay davor',
    (tester) async {
      await _overlaySettings('whisper-base');
      final results = <String>[];
      for (var r = 0; r < _rounds; r++) {
        for (final overlayFirst in [false, true]) {
          if (overlayFirst) await _useOverlay(e2e);
          final answer = (r + (overlayFirst ? 1 : 0)).isEven ? 'nein' : 'ja';
          final exit = await d3(tester, 'whisper-base', answer);
          results.add(
            '${overlayFirst ? 'nach Overlay' : 'ohne Overlay'} $answer: '
            '${RegExp(r'reason=(\S+)').firstMatch(exit)![1]}',
          );
        }
      }
      final listened = results.where((r) => r.contains('answered(')).length;
      final tap = results.length - listened;
      // ignore: avoid_print
      print(
        'WP30-Messung B7: ${results.length} Durchläufe, zugehört und '
        'beantwortet $listened, „Antworte per Tipp“ $tap, still 0\n'
        '${results.join('\n')}',
      );
      for (final r in results) {
        final ja = r.contains(' ja: ');
        expect(
          r,
          anyOf(
            contains(ja ? 'answered(yes)' : 'answered(no)'),
            contains('capture-null'),
            contains('unclear'),
          ),
        );
      }
    },
    skip: !voiceE2e,
    timeout: Timeout(Duration(minutes: 4 + 3 * _rounds)),
  );

  testWidgets(
    'B11/B14: erster Tipp nach dem Start (small), App und Overlay, Speicher',
    (tester) async {
      await _overlaySettings('whisper-small');
      // App: first tap right after the start (no time to prewarm).
      final exit = await d3(tester, 'whisper-small', 'nein');
      expect(exit, contains('answered(no)'));
      final startLine = lines.length;
      final loadsBefore = lines
          .where((l) => l.contains(' model-load ') && l.contains('small'))
          .length;
      final ready = lines.lastWhere((l) => l.contains(' mic-ready '));
      // ignore: avoid_print
      print('WP30-Messung B11 erster Tipp nach dem Start: $ready');

      // Keep an app engine with small loaded while the overlay is used.
      final e2eApp = E2eApp(startup: const StartupSettings());
      await e2eApp.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(sttModel: 'whisper-small'),
      );
      final c = await e2eApp.pump(tester);
      await c.read(speechToTextProvider.future);
      await _useOverlay(e2e);
      await askHost('meminfo');
      final mem = File('${e2e.path}/meminfo.txt').readAsStringSync();
      final loads =
          lines
              .where((l) => l.contains(' model-load ') && l.contains('small'))
              .length -
          loadsBefore;
      // At most one model at a time: every model-load after the app tap
      // shows live=1, and a load never follows a load without a model-free.
      var open = 0;
      for (final l in lines.skip(startLine)) {
        if (l.contains(' model-load ') && l.contains('whisper')) {
          open++;
          expect(open, lessThanOrEqualTo(1), reason: 'zwei Modelle live: $l');
          final live = RegExp(r'live=(\d+)').firstMatch(l);
          if (live != null) {
            expect(int.parse(live[1]!), lessThanOrEqualTo(1), reason: l);
          }
        } else if (l.contains(' model-free ') && l.contains('whisper')) {
          open = open > 0 ? open - 1 : 0;
        }
      }
      // ignore: avoid_print
      print(
        'WP30-Messung B14 (Debug-Build, small, App + Overlay): '
        'model-load whisper-small in der App-Engine $loads×\n$mem',
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: !voiceE2e,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
