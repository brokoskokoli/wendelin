import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, frame, runFake, settle;

/// WP195: nothing heard in the first round ends quietly.
void main() {
  group('nichts gehört (erste Runde)', () {
    test(
      'erste Runde: 5-s-Grenze in Mikrofon-Samples (166 vs. 167 Frames)',
      () {
        runFake((async) {
          // Frames zu 30 ms: 166 Frames = 4,98 s, 167 Frames = 5,01 s.
          final h = Harness();
          h.fakeAudio.script(AudioFrames.pattern('.' * 166, frame: frame));
          h.pipeline.start();
          async.elapse(const Duration(milliseconds: 6000)); // < 5 s + Grace
          expect(h.eventsOf<VoiceNothingHeard>(), isEmpty);
          expect(h.pipeline.state, VoiceState.listening);
          h.pipeline.cancel();
          settle(async);

          final h2 = Harness();
          h2.fakeAudio.script(AudioFrames.pattern('.' * 167, frame: frame));
          h2.pipeline.start();
          async.elapse(const Duration(milliseconds: 5100));
          expect(h2.eventsOf<VoiceNothingHeard>(), hasLength(1));
          expect(h2.tts.spoken, isEmpty);
        });
      },
    );

    test('erste Runde: Wanduhr-Schutz bei 5 s + listenGrace', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(listenGrace: Duration(seconds: 1)),
        );
        h.fakeAudio.script(const []);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 5900));
        expect(h.eventsOf<VoiceNothingHeard>(), isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        expect(h.eventsOf<VoiceNothingHeard>(), hasLength(1));
      });
    });

    test('Sprache, aber leeres Transkript: weiter „nicht verstanden“', () {
      runFake((async) {
        final h = Harness(transcripts: const [Transcript(text: '  ')]);
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceNothingUnderstood>(), hasLength(1));
        expect(h.eventsOf<VoiceNothingHeard>(), isEmpty);
        expect(h.tts.spoken, [VoiceTexts.de.nothingUnderstood]);
      });
    });
  });
}
