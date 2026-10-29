import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, frame, runFake, settle;

void main() {
  group('VoicePipeline mit ContinuousAudioInput (WP178)', () {
    test('Aufnahme bricht zwischen Phasen nicht ab, läuft bei Sprachausgabe weiter', () {
      runFake((async) {
        final rawMic = FakeAudioInput(
          frames: AudioFrames.pattern(
            // Turn 1 (Frage 1)
            '${'.' * 5}${'S' * 20}${'.' * 30}'
            // Während Sprachausgabe (20 Frames)
            '${'.' * 20}'
            // Turn 2 (Folgefrage)
            '${'.' * 5}${'S' * 20}${'.' * 30}',
            frame: frame,
          ),
          frameInterval: frame,
        );
        final continuousMic = ContinuousAudioInput(rawMic);

        final h = Harness(
          audio: continuousMic,
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 5),
          ),
          transcripts: const [
            Transcript(text: 'Wie spät ist es?'),
            Transcript(text: 'Und das Wetter?'),
          ],
          turns: [
            ScriptedTurn.text('Es ist zwölf Uhr.'),
            ScriptedTurn.text('Die Sonne scheint.'),
          ],
        );

        expect(rawMic.isRunning, isFalse);
        expect(rawMic.startCount, 0);

        // Wendelin beginnt zuzuhören
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 100));

        // Aufnahme läuft ab dem Moment, wo Wendelin zuhört
        expect(rawMic.isRunning, isTrue);
        expect(rawMic.startCount, 1);

        // Turn 1 abarbeiten
        settle(async);

        expect(h.tts.spoken, contains('Es ist zwölf Uhr.'));
        expect(
          h.recording.inputs.map((i) => i.text),
          contains('Wie spät ist es?'),
        );

        // Auch nach der ersten Antwort und vor/während Turn 2 läuft die Aufnahme weiter!
        // Kein ständiges Neustarten / Stoppen des Mikrofons:
        expect(rawMic.isRunning, isTrue);
        expect(rawMic.startCount, 1); // Immer noch genau 1 Start!

        // Turn 2 abarbeiten
        settle(async);

        expect(h.tts.spoken, contains('Die Sonne scheint.'));
        expect(
          h.recording.inputs.map((i) => i.text),
          contains('Und das Wetter?'),
        );

        // Immer noch 1 Start!
        expect(rawMic.startCount, 1);

        // Am Ende (wenn die Konversation beendet wird):
        h.pipeline.cancel();
        unawaited(continuousMic.close());
        settle(async);

        expect(rawMic.isRunning, isFalse);
      });
    });
  });
}
