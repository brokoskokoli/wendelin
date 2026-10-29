// WP153: Entsperren, während schon eine Anfrage läuft (Erkennung oder
// Folge-Zuhören): sie läuft entsperrt weiter, kein neuer Trigger, kein
// „Abgebrochen“, das Fenster bleibt offen.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show utterance;
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

Future<void> _pump(WidgetTester t, [int n = 60]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeLlmProvider llm;
  late TestEnv env;
  late FakeAssistantPlatform platform;
  late FakeTextToSpeech tts;
  late List<String> logs;
  late void Function(String) savedSink;

  setUp(() {
    llm = FakeLlmProvider([ScriptedTurn.text('Es ist zehn Uhr.')]);
    env = TestEnv(providerConfig: scripted(llm), enabled: const {'memory'});
    platform = FakeAssistantPlatform()..locked = true;
    tts = FakeTextToSpeech();
    logs = [];
    savedSink = voiceLogSink;
    voiceLogSink = logs.add;
  });
  tearDown(() => voiceLogSink = savedSink);

  // The `by` of every close the overlay logged.
  List<String> closes() => [
    for (final l in logs)
      if (l.contains('overlay-close'))
        RegExp(r'by=(\S+)').firstMatch(l)!.group(1)!,
  ];

  Future<ProviderContainer> open(
    WidgetTester tester,
    FakeSpeechToText stt, {
    bool conversation = false,
  }) => pumpOverlay(
    tester,
    env,
    platform,
    voice: VoiceComponents(
      audio: FakeAudioInput(
        frames: utterance(),
        frameInterval: const Duration(milliseconds: 30),
      ),
      vad: FakeVoiceActivityDetector(),
      stt: stt,
      textToSpeech: (_) async => tts,
      config: VoicePipelineConfig(conversationMode: conversation),
    ),
  );

  testWidgets('Entsperren während der Erkennung: Anfrage läuft entsperrt '
      'weiter, Fenster offen, nichts abgebrochen', (tester) async {
    platform.unlockSucceeds = true;
    final stt = FakeSpeechToText([
      const Transcript(text: 'Wie spät ist es', language: 'de'),
    ])..hold = true;
    final c = await open(tester, stt);
    for (var i = 0; i < 100 && stt.calls.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(stt.calls, hasLength(1), reason: 'Erkennung läuft');
    await tester.tap(find.text(AppLocalizationsDe().overlayUnlock));
    await _pump(tester, 4);
    stt.release();
    await _pump(tester);

    expect(stt.calls, hasLength(1), reason: 'kein neuer Trigger');
    expect(llm.requests, hasLength(1), reason: 'Anfrage lief weiter');
    expect(c.read(voiceControllerProvider).stopCount, 0);
    // WP172: the window closes after the answer, not by the unlock.
    expect(platform.finished, 1, reason: 'schliesst erst nach der Antwort');
    final entries = c.read(agentControllerProvider).entries;
    expect(entries.whereType<UserEntry>().single.text, 'Wie spät ist es');
    expect(logs.where((l) => l.contains('voice-cancelled')), isEmpty);
    expect(closes(), ['idle']);
    expect(tts.spoken.any((s) => s.contains('zehn')), isTrue);
  });

  testWidgets('Folge-Zuhören + gemerkte Anfrage: Antwort wird gesprochen, '
      'kein „Abgebrochen“', (tester) async {
    platform.unlockGate = Completer<bool>();
    final c = await open(
      tester,
      FakeSpeechToText([
        const Transcript(text: 'Wie spät ist es', language: 'de'),
      ]),
      conversation: true,
    );
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (c.read(voiceControllerProvider).followUpUntil != null) break;
    }
    expect(c.read(voiceControllerProvider).followUpUntil, isNotNull);
    expect(llm.requests, isEmpty, reason: 'gesperrt: nichts läuft');
    await tester.tap(find.text(AppLocalizationsDe().overlayUnlock));
    await _pump(tester, 2);
    platform.unlockGate!.complete(true);
    await _pump(tester, 100);

    expect(llm.requests, hasLength(1));
    expect(
      tts.spoken.any((s) => s.contains('zehn')),
      isTrue,
      reason: 'gesprochen',
    );
    expect(c.read(voiceControllerProvider).stopCount, 0);
    expect(platform.finished, 1, reason: 'WP172: schliesst nach der Antwort');
    expect(closes(), ['idle']);
    expect(
      logs.where((l) => l.contains('voice-cancelled reason=tap')),
      isEmpty,
    );
  });

  testWidgets('Entsperren abgebrochen während der Erkennung: kein Modellaufruf '
      '(gesperrt, fail closed), Hinweis, Fenster offen', (tester) async {
    platform.unlockSucceeds = false;
    final stt = FakeSpeechToText([
      const Transcript(text: 'Wie spät ist es', language: 'de'),
    ])..hold = true;
    await open(tester, stt);
    for (var i = 0; i < 100 && stt.calls.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text(AppLocalizationsDe().overlayUnlock));
    await _pump(tester, 4);
    stt.release();
    await _pump(tester);
    expect(llm.requests, isEmpty);
    expect(platform.finished, 0);
  });

  testWidgets('Entsperren bei laufender getippter Anfrage (ohne gemerkte): '
      'kein neuer Trigger, der Lauf geht weiter', (tester) async {
    AssistantOverlayScreen.closeWhenIdle = false; // the test cancels the voice itself (not the overlay), nothing runs yet (WP172)
    platform.unlockSucceeds = true;
    llm = FakeLlmProvider([ScriptedTurn.hang()]);
    env = TestEnv(providerConfig: scripted(llm), enabled: const {'memory'});
    final stt = FakeSpeechToText(const []);
    final c = await open(tester, stt);
    await c
        .read(voiceControllerProvider.notifier)
        .cancel(VoiceCancelReason.retrigger);
    await _pump(tester, 4);
    expect(c.read(voiceControllerProvider).active, isFalse);
    unawaited(c.read(agentControllerProvider.notifier).send('Tippen'));
    await _pump(tester, 4);
    expect(c.read(agentControllerProvider).running, isTrue);
    logs.clear();
    final calls = stt.calls.length;
    final cancels = c.read(voiceControllerProvider).stopCount;

    await tester.tap(find.text(AppLocalizationsDe().overlayUnlock));
    await _pump(tester, 20);

    expect(c.read(voiceControllerProvider).active, isFalse, reason: 'Trigger');
    expect(stt.calls.length, calls);
    expect(c.read(agentControllerProvider).running, isTrue, reason: 'Lauf');
    expect(c.read(voiceControllerProvider).stopCount, cancels);
    expect(platform.finished, 0);
    expect(logs.where((l) => l.contains('voice-cancelled')), isEmpty);
  });

  testWidgets('zweiter Trigger bei laufender Aufnahme: Neustart, kein '
      '„Abgebrochen“, Fenster bleibt', (tester) async {
    platform.locked = false;
    final stt = FakeSpeechToText([
      const Transcript(text: 'Wie spät ist es', language: 'de'),
    ]);
    final c = await open(tester, stt);
    await _pump(tester, 3);
    expect(c.read(voiceControllerProvider).active, isTrue);
    platform.trigger();
    await _pump(tester, 100);
    expect(c.read(voiceControllerProvider).stopCount, 0);
    // The retrigger itself did not close; the answer to the new request does.
    expect(closes(), ['idle']);
    expect(platform.finished, 1);
    expect(
      logs.where((l) => l.contains('voice-cancelled reason=tap')),
      isEmpty,
    );
  });
}
