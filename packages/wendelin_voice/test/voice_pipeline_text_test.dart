import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, runFake, settle;

void main() {
  test('answerText: Text wird beantwortet und vorgelesen, ohne Mikrofon', () {
    runFake((async) {
      final h = Harness(turns: [ScriptedTurn.text('Es ist zehn Uhr.')]);
      expect(h.pipeline.answerText('Wie spät ist es'), isTrue);
      expect(
        h.pipeline.answerText('noch eins'),
        isFalse,
        reason: 'beschäftigt',
      );
      settle(async);
      expect(h.states, [
        VoiceState.thinking,
        VoiceState.speaking,
        VoiceState.idle,
      ]);
      expect(h.recording.inputs.single.text, 'Wie spät ist es');
      expect(h.tts.spoken, ['Es ist zehn Uhr.']);
      expect(h.fakeAudio.isRunning, isFalse);
      expect(h.stt.calls, isEmpty);
    });
  });
}
