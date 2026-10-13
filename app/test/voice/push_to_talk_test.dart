import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/main_parts.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../screens/main_screen_test.dart' show pumpApp, pumpUntil;
import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice, utterance;

MicState micState(WidgetTester tester) =>
    tester.widget<MicButton>(find.byType(MicButton)).state;

void main() {
  testWidgets(
    'Hauptbildschirm: Mikrofon → Zuhören → Denken → Antwort gesprochen',
    (tester) async {
      final tts = FakeTextToSpeech();
      final audio = FakeAudioInput(
        frames: utterance(),
        frameInterval: const Duration(milliseconds: 30),
      );
      final env = TestEnv(
        providerConfig: scripted(
          FakeLlmProvider([ScriptedTurn.text('Morgen wird es sonnig.')]),
        ),
        extraOverrides: [
          voiceComponentsProvider.overrideWith(
            (ref) async => fakeVoice(
              audio: audio,
              tts: tts,
              script: const [Transcript(text: 'Wie wird das Wetter?')],
            ),
          ),
        ],
      );
      await pumpApp(tester, env);
      await tester.pump();
      expect(micState(tester), MicState.idle);

      await tester.tap(find.byType(MicButton));
      await tester.pump(const Duration(milliseconds: 60));
      expect(micState(tester), MicState.listening);
      expect(find.byTooltip(Composer.listeningLabel), findsOneWidget);
      expect(find.text('Ich höre zu …'), findsOneWidget);

      await pumpUntil(tester, find.text('Wie wird das Wetter?'));
      await pumpUntil(tester, find.text('Morgen wird es sonnig.'));
      for (var i = 0; i < 20 && micState(tester) != MicState.idle; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(micState(tester), MicState.idle);
      expect(tts.spoken, ['Morgen wird es sonnig.']);
      expect(audio.isRunning, isFalse);
    },
  );

  testWidgets('Antippen beim Denken bricht ab', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([ScriptedTurn.hang(partialText: 'Moment')]),
      ),
      extraOverrides: [
        voiceComponentsProvider.overrideWith(
          (ref) async =>
              fakeVoice(script: const [Transcript(text: 'Erzähl was')]),
        ),
      ],
    );
    await pumpApp(tester, env);
    await tester.pump();
    await tester.tap(find.byType(MicButton));
    await pumpUntil(tester, find.text('Moment'));
    expect(micState(tester), MicState.thinking);
    expect(find.byTooltip('Antwort abbrechen'), findsOneWidget);

    await tester.tap(find.byType(MicButton));
    for (var i = 0; i < 20 && micState(tester) != MicState.idle; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(micState(tester), MicState.idle);
  });

  testWidgets('Bestätigung: Sheet zeigt Sprachhinweis, „Ja“ per Stimme', (
    tester,
  ) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Gelöscht.'),
        ]),
      ),
      extraOverrides: [
        voiceComponentsProvider.overrideWith(
          (ref) async => fakeVoice(
            audio: FakeAudioInput(
              frames: utterance(),
              frameInterval: const Duration(milliseconds: 30),
            ),
            script: const [
              Transcript(text: 'Lösch den Zahnarzttermin'),
              Transcript(text: 'Ja'),
            ],
          ),
        ),
      ],
    );
    await env.calendar.createEvent(zahnarztDraft());
    await pumpApp(tester, env);
    await tester.pump();
    await tester.tap(find.byType(MicButton));
    await pumpUntil(tester, find.text('Sag einfach „ja“ oder „nein“'));
    expect(find.text('Termin löschen?'), findsOneWidget);
    await pumpUntil(tester, find.text('Gelöscht.'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Termin löschen?'), findsNothing);
    expect(env.calendar.events, isEmpty);
  });

  testWidgets('getippte Anfrage: Bestätigung nur per Tipp', (tester) async {
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([
          ScriptedTurn.toolCalls([
            call('c1', 'calendar__delete_event', '{"event_id":"e1"}'),
          ]),
          ScriptedTurn.text('Gut.'),
        ]),
      ),
    );
    await env.calendar.createEvent(zahnarztDraft());
    await pumpApp(tester, env);
    await tester.enterText(find.byType(TextField), 'Lösch den Termin');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await pumpUntil(tester, find.text('Antworte per Tipp'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Nein, behalten'));
    await pumpUntil(tester, find.text('Gut.'));
    expect(env.calendar.events, hasLength(1));
  });

  testWidgets('App im Hintergrund: Mikrofon aus, Sprachausgabe gestoppt', (
    tester,
  ) async {
    final tts = FakeTextToSpeech(manual: true);
    final audio = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 500),
      frameInterval: const Duration(milliseconds: 10),
    );
    final components = fakeVoice(
      audio: audio,
      tts: tts,
      script: const [Transcript(text: 'Erzähl was')],
    );
    final env = TestEnv(
      providerConfig: scripted(
        FakeLlmProvider([ScriptedTurn.text('Ein Satz. Noch einer.')]),
      ),
      extraOverrides: [
        voiceComponentsProvider.overrideWith((ref) async => components),
      ],
    );
    await pumpApp(tester, env);
    await tester.pump();
    await tester.tap(find.byType(MicButton));
    await tester.pump(const Duration(milliseconds: 50));
    expect(audio.isRunning, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 50));
    expect(audio.isRunning, isFalse);
    expect(micState(tester), MicState.idle);

    // Zurück, Antwort wird gesprochen, dann wieder weg: TTS stoppt.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    audio.script(utterance());
    await tester.tap(find.byType(MicButton));
    for (var i = 0; i < 100 && tts.state != TtsState.speaking; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(tts.state, TtsState.speaking);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(const Duration(milliseconds: 50));
    expect(tts.state, TtsState.idle);
    expect(tts.interrupted, contains('Ein Satz.'));
    expect(micState(tester), MicState.idle);
  });
}
