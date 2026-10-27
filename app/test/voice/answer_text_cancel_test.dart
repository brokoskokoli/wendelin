// WP114 (K85): „Entsperren“ beantwortet die gemerkte Anfrage laut. Wird die
// Stimme abgebrochen, während die Modelle noch laden, startet nichts.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';

void main() {
  test('answerText: Abbruch während des Ladens, keine Anfrage und keine '
      'Sprache; true: der Aufrufer sendet nicht als Text', () async {
    final warm = Completer<void>();
    final tts = FakeTextToSpeech();
    final llm = FakeLlmProvider([ScriptedTurn.text('Es ist zehn Uhr.')]);
    final env = TestEnv(
      providerConfig: scripted(llm),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: FakeAudioInput(),
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText(const []),
            textToSpeech: (_) async => tts,
            config: const VoicePipelineConfig(),
            warmUp: () => warm.future,
          ),
        ),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    final voice = c.read(voiceControllerProvider.notifier);

    final answered = voice.answerText('Wie spät ist es');
    await pumpEventQueue();
    await voice.cancel(); // z. B. Home nach der Gnadenfrist
    warm.complete();

    expect(
      await answered,
      isTrue,
      reason: 'abgebrochen, nicht als Text nachsenden',
    );
    await voice.whenIdle;
    expect(llm.requests, isEmpty);
    expect(tts.spoken, isEmpty);
    expect(c.read(agentControllerProvider).entries, isEmpty);
  });

  // WP153: Entsperren, während der Sperr-Hinweis noch gesprochen wird.
  ProviderContainer build(FakeLlmProvider llm, FakeTextToSpeech tts) {
    final env = TestEnv(
      providerConfig: scripted(llm),
      extraOverrides: [
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: FakeAudioInput(),
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText(const []),
            textToSpeech: (_) async => tts,
            config: const VoicePipelineConfig(),
          ),
        ),
      ],
    );
    final c = env.container();
    addTearDown(c.dispose);
    return c;
  }

  test('answerText: spricht noch der Hinweis, wird er beendet und die '
      'Anfrage gesprochen beantwortet (true, nicht als Text)', () async {
    final tts = FakeTextToSpeech(manual: true);
    final llm = FakeLlmProvider([
      ScriptedTurn.text('Bitte entsperre das Gerät.'),
      ScriptedTurn.text('Es ist zehn Uhr.'),
    ]);
    final c = build(llm, tts);
    final voice = c.read(voiceControllerProvider.notifier);
    expect(await voice.answerText('Hinweis auslösen'), isTrue);
    for (var i = 0; i < 50 && tts.spoken.isEmpty; i++) {
      await pumpEventQueue();
    }
    expect(tts.spoken, hasLength(1), reason: 'Hinweis wird gesprochen');

    expect(await voice.answerText('Wie spät ist es'), isTrue);
    for (var i = 0; i < 50 && tts.spoken.length < 2; i++) {
      await pumpEventQueue();
    }
    expect(tts.interrupted, hasLength(1), reason: 'Hinweis beendet');
    expect(tts.spoken.last, contains('zehn'));
    expect(llm.requests, hasLength(2));
    tts.completeCurrent();
    await voice.whenIdle;
  });

  test('answerText: arbeitet gerade eine Anfrage, bleibt sie unberührt '
      '(false: der Aufrufer sendet als Text)', () async {
    final tts = FakeTextToSpeech();
    final llm = FakeLlmProvider([ScriptedTurn.hang()]);
    final c = build(llm, tts);
    final voice = c.read(voiceControllerProvider.notifier);
    expect(await voice.answerText('Erste'), isTrue);
    for (var i = 0; i < 50 && llm.requests.isEmpty; i++) {
      await pumpEventQueue();
    }
    expect(await voice.answerText('Zweite'), isFalse);
    expect(llm.requests, hasLength(1));
    expect(c.read(voiceControllerProvider).stopCount, 0);
    expect(
      c.read(agentControllerProvider).running,
      isTrue,
      reason: 'laufende Anfrage nicht abgebrochen',
    );
    await voice.cancel();
  });
}
