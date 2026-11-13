// WP93: a wake word hit with the chat visible continues the conversation in
// the chat; settings open, app paused or device locked leave it to the
// overlay.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/agent_providers.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/platform/wake/wake_platform.dart';
import 'package:wendelin/ui/screens/main_screen.dart';
import 'package:wendelin/voice/speaker/speaker_storage.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_chat.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../agent/person_scope_test.dart' show testProfile;
import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';
import '../ui/helpers.dart';
import '../voice/voice_controller_test.dart' show fakeVoice, utterance;
import 'main_screen_test.dart' show containerOf, pumpApp;

/// Stand-in for the Kotlin side of the wake word service (main app).
final class FakeWakePlatform extends WakePlatform {
  @override
  Future<void> setTexts(Map<String, String> texts) async {}

  Future<bool> Function()? handler;
  final visible = <bool>[];
  int done = 0;

  /// Called on every `chatDone` (tests record the state at that moment).
  void Function()? onDone;

  @override
  set onWakeHit(Future<bool> Function()? h) => handler = h;

  @override
  Future<bool> Function()? get onWakeHit => handler;

  @override
  Future<void> setChatVisible({required bool visible}) async =>
      this.visible.add(visible);

  @override
  Future<void> chatDone() async {
    done++;
    onDone?.call();
  }

  /// The service asks the main engine.
  Future<bool> hit() => handler?.call() ?? Future.value(false);
}

void main() {
  late FakeWakePlatform wake;
  late FakeAssistantPlatform assistant;
  final logLines = <String>[];
  late void Function(String) savedSink;
  setUp(() {
    logLines.clear();
    savedSink = voiceLogSink;
    voiceLogSink = logLines.add;
  });
  tearDown(() => voiceLogSink = savedSink);

  Future<void> pump(
    WidgetTester tester, {
    bool handoff = true,
    List<ScriptedTurn>? turns,
    VoiceComponents? voice,
    bool ready = true,
    bool noModels = false,
    Future<void> Function(TestEnv env)? setup,
  }) async {
    wake = FakeWakePlatform();
    assistant = FakeAssistantPlatform();
    if (handoff) {
      assistant.wakeHandoff = Int16List.fromList(List.filled(8000, 300));
    }
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider(turns ?? [ScriptedTurn.text('ok')]),
      ),
      extraOverrides: [
        wakePlatformProvider.overrideWithValue(wake),
        assistantPlatformProvider.overrideWithValue(assistant),
        voiceReadyProvider.overrideWithValue(ready),
        wakeConfirmToneProvider.overrideWithValue(() async {}),
        activeVoiceProvider.overrideWith(
          (ref) async => noModels
              ? null
              : voice ??
                    fakeVoice(
                      script: const [
                        Transcript(
                          text: 'Wie wird das Wetter?',
                          language: 'de',
                        ),
                      ],
                    ),
        ),
      ],
    );
    await setup?.call(env);
    await pumpApp(tester, env);
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// Quiet frames first: the confirmation tone mutes the start of the
  /// microphone, speech must not begin inside it.
  List<Int16List> speech() => [
    for (var i = 0; i < 10; i++) Int16List.fromList(List.filled(480, 100)),
    ...utterance(),
  ];

  /// Speech that arrives in real time (frames with an interval), so the
  /// pipeline hears it after the hit.
  VoiceComponents speaking(
    List<Transcript> script, {
    FakeAudioInput? audio,
    VoicePipelineConfig config = const VoicePipelineConfig(),
    bool tts = false,
  }) => VoiceComponents(
    audio:
        audio ??
        FakeAudioInput(
          frames: speech(),
          frameInterval: const Duration(milliseconds: 30),
        ),
    vad: FakeVoiceActivityDetector(),
    stt: FakeSpeechToText(script),
    textToSpeech: (_) async => tts ? FakeTextToSpeech() : null,
    config: config,
  );

  Future<bool> askHit(WidgetTester tester) async {
    bool? answer;
    unawaited(wake.hit().then((v) => answer = v));
    await pumpUntil(tester, () => answer != null);
    return answer!;
  }

  testWidgets(
    'Chat sichtbar: der Chat hört zu, danach hört der Dienst wieder',
    (tester) async {
      await pump(tester);
      expect(wake.visible, [true]);
      final c = containerOf(tester);
      final triggers = <TriggerKind?>[];
      c.listen(voiceControllerProvider.select((v) => v.trigger), (_, t) {
        triggers.add(t);
      });
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => wake.done > 0);
      expect(triggers, contains(TriggerKind.wakeWord));
      expect(assistant.wakeTakes, 1);
      expect(wake.done, 1);
    },
  );

  testWidgets('Einstellungen offen: Overlay, der Chat nimmt nichts', (
    tester,
  ) async {
    await pump(tester);
    unawaited(
      Navigator.of(tester.element(find.byType(MainScreen))).push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Zwei'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(wake.visible, [true, false]);
    // Race: the service still holds an old flag, the chat looks again.
    expect(await askHit(tester), isFalse);
    expect(assistant.wakeTakes, 0);
    expect(containerOf(tester).read(voiceControllerProvider).active, isFalse);
  });

  testWidgets('Dialog über dem Chat: Overlay', (tester) async {
    await pump(tester);
    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(MainScreen)),
        builder: (_) => const AlertDialog(title: Text('Frage')),
      ),
    );
    await tester.pumpAndSettle();
    expect(await askHit(tester), isFalse);
    expect(assistant.wakeTakes, 0);
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    expect(wake.visible.last, isTrue);
  });

  testWidgets('App pausiert: Overlay; wieder da: Chat', (tester) async {
    await pump(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(wake.visible.last, isFalse);
    expect(await askHit(tester), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(wake.visible.last, isTrue);
    expect(await askHit(tester), isTrue);
  });

  testWidgets('Gerät gesperrt: Overlay', (tester) async {
    await pump(tester);
    assistant.locked = true;
    expect(await askHit(tester), isFalse);
    expect(assistant.wakeTakes, 0);
  });

  // The chatDone of a chat that lost the hit is ignored by the service
  // (ChatState.release, WakePolicyTest); here: it never listens besides.
  testWidgets('Pre-Roll schon vergeben: kein zweiter Zuhörer', (tester) async {
    await pump(tester, handoff: false);
    expect(await askHit(tester), isTrue);
    final c = containerOf(tester);
    await pumpUntil(tester, () => wake.done > 0);
    expect(c.read(voiceControllerProvider).active, isFalse);
    expect(logLines.where((l) => l.contains('voice-cancelled')), isEmpty);
  });

  testWidgets('Bildschirm weg während des Zuhörens: Dienst hört wieder', (
    tester,
  ) async {
    await pump(tester);
    expect(await askHit(tester), isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(wake.done, 1);
    expect(wake.handler, isNull);
  });

  group('Zugende und Gesprächsmodus', () {
    testWidgets('Gesprächsmodus: Folgefenster offen, Dienst bleibt stumm', (
      tester,
    ) async {
      final audio = FakeAudioInput(
        frames: speech(),
        frameInterval: const Duration(milliseconds: 30),
      );
      await pump(
        tester,
        voice: speaking(
          const [Transcript(text: 'Wie wird das Wetter?', language: 'de')],
          audio: audio,
          tts: true,
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 30),
          ),
        ),
      );
      final c = containerOf(tester);
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => audio.startCount == 1);
      // The follow-up window listens to silence.
      audio.script(AudioFrames.pattern('.' * 2000));
      await pumpUntil(tester, () => c.read(voiceControllerProvider).followUp);
      // Far beyond the idle delay: the window keeps the service quiet.
      await tester.pump(const Duration(seconds: 2));
      expect(c.read(voiceControllerProvider).followUp, isTrue);
      expect(wake.done, 0);
      await tester.pumpWidget(const SizedBox());
      expect(wake.done, 1);
    });

    testWidgets('Agent läuft beim Treffer: Handoff frei, Dienst bleibt stumm', (
      tester,
    ) async {
      await pump(tester, turns: [ScriptedTurn.hang()]);
      final c = containerOf(tester);
      unawaited(c.read(agentControllerProvider.notifier).send('Los'));
      await pumpUntil(tester, () => c.read(agentControllerProvider).running);
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => assistant.wakeTakes == 1);
      expect(c.read(voiceControllerProvider).active, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(wake.done, 0, reason: 'der Agent läuft noch');
      c.read(agentControllerProvider.notifier).cancel();
      await pumpUntil(tester, () => wake.done == 1);
    });

    testWidgets('kein chatDone in der Lücke zwischen Zuhören und Anfrage', (
      tester,
    ) async {
      await pump(
        tester,
        voice: speaking(const [
          Transcript(text: 'Wie wird das Wetter?', language: 'de'),
        ]),
      );
      final c = containerOf(tester);
      var ran = false;
      c.listen(agentControllerProvider.select((s) => s.running), (_, r) {
        ran = ran || r;
      });
      var ranAtDone = false;
      wake.onDone = () => ranAtDone = ran;
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => wake.done > 0);
      expect(ranAtDone, isTrue, reason: 'erst nach der Anfrage');
    });

    testWidgets('Start abgelehnt: der Handoff wird freigegeben', (
      tester,
    ) async {
      await pump(tester, ready: false, noModels: true);
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => wake.done == 1);
      expect(assistant.wakeTakes, 1);
      expect(containerOf(tester).read(voiceControllerProvider).active, isFalse);
    });

    testWidgets('Ruhefenster und Folgefenster: kein vorzeitiges chatDone', (
      tester,
    ) async {
      await pump(tester, ready: false, noModels: true);
      final c = containerOf(tester);
      expect(await askHit(tester), isTrue);
      await pumpUntil(tester, () => assistant.wakeTakes == 1);
      // Idle right away, but the short pause is no end yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(wake.done, 0);
      // A follow-up window opens in the gap: still no end.
      final voice = c.read(voiceControllerProvider.notifier);
      // ignore: invalid_use_of_protected_member
      voice.state = VoiceUiState(followUpUntil: DateTime.utc(2030));
      await tester.pump(const Duration(seconds: 2));
      expect(wake.done, 0);
      // ignore: invalid_use_of_protected_member
      voice.state = const VoiceUiState();
      await tester.pump(const Duration(seconds: 1));
      expect(wake.done, 1);
    });

    testWidgets('Treffer beim Zuhören: das alte Zuhören wird abgebrochen', (
      tester,
    ) async {
      final audio = FakeAudioInput(
        frames: AudioFrames.pattern('.' * 2000),
        frameInterval: const Duration(milliseconds: 30),
      );
      await pump(
        tester,
        voice: speaking(const [
          Transcript(text: 'Wie wird das Wetter?', language: 'de'),
        ], audio: audio),
      );
      final c = containerOf(tester);
      expect(
        await c
            .read(voiceControllerProvider.notifier)
            .start(TriggerKind.pushToTalk),
        isTrue,
      );
      expect(c.read(voiceControllerProvider).active, isTrue);
      logLines.clear();
      expect(await askHit(tester), isTrue);
      await pumpUntil(
        tester,
        () => logLines.any((l) => l.contains('voice-cancelled')),
      );
    });

    testWidgets('Antwort an Kotlin vor dem Take (normaler Pfad)', (
      tester,
    ) async {
      await pump(tester);
      var answered = false;
      bool? answeredAtTake;
      assistant.onTake = () => answeredAtTake ??= answered;
      unawaited(wake.hit().then((_) => answered = true));
      await pumpUntil(tester, () => assistant.wakeTakes == 1);
      expect(answeredAtTake, isTrue, reason: 'Kotlin kennt den Besitzer');
    });

    testWidgets('Antwort an Kotlin vor dem Take (Agent läuft)', (tester) async {
      await pump(tester, turns: [ScriptedTurn.hang()]);
      final c = containerOf(tester);
      unawaited(c.read(agentControllerProvider.notifier).send('Los'));
      await pumpUntil(tester, () => c.read(agentControllerProvider).running);
      var answered = false;
      bool? answeredAtTake;
      assistant.onTake = () => answeredAtTake ??= answered;
      unawaited(wake.hit().then((_) => answered = true));
      await pumpUntil(tester, () => assistant.wakeTakes == 1);
      expect(answeredAtTake, isTrue, reason: 'Kotlin kennt den Besitzer');
      c.read(agentControllerProvider.notifier).cancel();
      await pumpUntil(tester, () => wake.done == 1);
    });

    for (final ready in [true, false]) {
      testWidgets(
        'Pre-Roll verloren: das Chat-Mikro öffnet nicht (ready $ready)',
        (tester) async {
          final audio = FakeAudioInput(frames: speech());
          await pump(
            tester,
            handoff: false,
            ready: ready,
            voice: speaking(const [
              Transcript(text: 'Wie wird das Wetter?', language: 'de'),
            ], audio: audio),
          );
          // The fake microphone is the one the start would open.
          await containerOf(tester).read(activeVoiceProvider.future);
          var everActive = false;
          containerOf(tester).listen(voiceControllerProvider, (_, v) {
            everActive = everActive || v.phase != VoiceState.idle;
          });
          expect(await askHit(tester), isTrue);
          await pumpUntil(tester, () => wake.done > 0);
          expect(everActive, isFalse);
          expect(audio.startCount, 0);
          expect(
            containerOf(tester).read(voiceControllerProvider).active,
            isFalse,
          );
        },
      );
    }

    for (final ready in [true, false]) {
      testWidgets('kein chatDone, solange der Start läuft (ready $ready)', (
        tester,
      ) async {
        await pump(tester, ready: ready);
        assistant.takeGate = Completer<void>();
        expect(await askHit(tester), isTrue);
        await pumpUntil(tester, () => assistant.wakeTakes == 1);
        await tester.pump(const Duration(seconds: 2));
        expect(wake.done, 0, reason: 'der Start hängt noch am Take');
        assistant.takeGate!.complete();
        await pumpUntil(tester, () => wake.done == 1);
      });
    }
    testWidgets('Bildschirm weg ohne Treffer: kein chatDone', (tester) async {
      await pump(tester);
      await tester.pumpWidget(const SizedBox());
      expect(wake.done, 0);
    });

    testWidgets('Treffer angenommen, Bildschirm sofort weg: kein Start', (
      tester,
    ) async {
      final audio = FakeAudioInput(frames: speech());
      await pump(tester, voice: speaking(const [], audio: audio));
      final c = containerOf(tester);
      await c.read(activeVoiceProvider.future);
      var everActive = false;
      c.listen(voiceControllerProvider, (_, v) {
        everActive = everActive || v.phase != VoiceState.idle || v.preparing;
      });
      expect(await wake.hit(), isTrue);
      // Before the start timer runs (the container outlives the screen).
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SizedBox()),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(everActive, isFalse);
      expect(audio.startCount, 0);
      expect(assistant.wakeTakes, 0);
    });

    testWidgets('Bildschirm weg zwischen Frage und Antwort: keine Annahme', (
      tester,
    ) async {
      final lock = Completer<bool>();
      await pump(tester);
      assistant.lockAnswer = lock;
      final answer = wake.hit();
      await tester.pumpWidget(const SizedBox());
      lock.complete(false);
      expect(await answer, isFalse);
      expect(assistant.wakeTakes, 0);
    });
  });

  testWidgets('andere Person per Wake im Chat: neue Unterhaltung', (
    tester,
  ) async {
    SpeakerMatch who(String id) =>
        SpeakerMatch.known(personId: id, name: id, score: 0.9);
    final scripts = [
      Transcript(text: 'Eins', language: 'de', speaker: who('pa')),
      Transcript(text: 'Zwei', language: 'de', speaker: who('pb')),
    ];
    final audio = FakeAudioInput(
      frames: speech(),
      frameInterval: const Duration(milliseconds: 30),
    );
    await pump(
      tester,
      turns: [ScriptedTurn.text('a'), ScriptedTurn.text('b')],
      voice: speaking(scripts, audio: audio),
      setup: (env) async {
        final profiles = SecretSpeakerProfileStore(env.secrets);
        await profiles.save(testProfile('pa', 'Anna'));
        await profiles.save(testProfile('pb', 'Ben'));
      },
    );
    final c = containerOf(tester);
    String? session() => c.read(sessionManagerProvider).currentId;
    expect(await askHit(tester), isTrue);
    await pumpUntil(tester, () => wake.done == 1);
    final first = session();
    expect(first, isNotNull);
    assistant.wakeHandoff = Int16List.fromList(List.filled(8000, 300));
    audio.script(speech());
    expect(await askHit(tester), isTrue);
    await pumpUntil(tester, () => wake.done == 2);
    expect(session(), isNot(first));
  });

  group('WakeChatPolicy', () {
    test('nur sichtbar, oben und entsperrt', () {
      bool a(bool r, bool c, bool l) =>
          WakeChatPolicy.accepts(resumed: r, routeCurrent: c, locked: l);
      expect(a(true, true, false), isTrue);
      expect(a(false, true, false), isFalse);
      expect(a(true, false, false), isFalse);
      expect(a(true, true, true), isFalse);
    });
  });
}
