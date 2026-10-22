// WP114 (K85): „Entsperren“ beantwortet die gemerkte Anfrage laut. Wird die
// Stimme abgebrochen, während die Modelle noch laden, startet nichts.
import 'dart:async';

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
}
