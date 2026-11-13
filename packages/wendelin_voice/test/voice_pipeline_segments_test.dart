import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart' show ScriptedTurn;
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, frame, runFake, settle;

const _perFrame = 480; // 30 ms at 16 kHz

/// [seconds] of speech with 600 ms quiet gaps starting at each of [gaps] (s).
List<Int16List> _recording(int seconds, List<int> gaps) {
  final frames = seconds * 1000 ~/ 30;
  final gapFrames = {
    for (final g in gaps)
      for (var i = 0; i < 20; i++) g * 1000 ~/ 30 + i,
  };
  return AudioFrames.pattern(
    [for (var i = 0; i < frames; i++) gapFrames.contains(i) ? '.' : 'S'].join(),
    frame: frame,
  );
}

void main() {
  group('Lange Halteaufnahmen in Segmenten (WP192)', () {
    test('70 s Halten: 3 STT-Aufrufe, ein zusammengesetzter Text', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Ja.')],
          transcripts: const [
            Transcript(text: 'Eins', language: 'de', confidence: 0.9),
            Transcript(text: 'zwei', language: 'de', confidence: 0.6),
            Transcript(text: 'drei.', language: 'de', confidence: 0.8),
          ],
        );
        h.fakeAudio.script(_recording(70, [23, 46]));
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 80));
        expect(h.stt.calls, isEmpty);
        h.pipeline.release();
        settle(async);
        expect(h.stt.calls, hasLength(3));
        expect(
          h.stt.calls.every((c) => c.samples <= sttSegmentLimitSamples),
          isTrue,
        );
        final t = h.eventsOf<VoiceTranscribed>().single.transcript;
        expect(t.text, 'Eins zwei drei.');
        expect(t.confidence, 0.6);
        expect(t.language, 'de');
        expect(h.tts.spoken, ['Ja.']);
        // The first cut lies in the quiet gap (23.0-23.6 s).
        expect(
          h.stt.calls.first.samples,
          inInclusiveRange(23 * 16000, 23 * 16000 + 20 * _perFrame),
        );
      });
    });

    test('Aufnahme bis zur Grenze: genau ein Aufruf (wie bisher)', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(_recording(20, const []));
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 25));
        h.pipeline.release();
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(
          h.eventsOf<VoiceTranscribed>().single.transcript.text,
          isNotEmpty,
        );
      });
    });

    test(
      'Abbruch zwischen den Segmenten: kein weiterer Aufruf, kein Ergebnis',
      () {
        runFake((async) {
          final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
          h.fakeAudio.script(_recording(70, [23, 46]));
          h.stt.hold = true;
          h.pipeline.start(hold: true);
          async.elapse(const Duration(seconds: 80));
          h.pipeline.release();
          settle(async);
          expect(h.stt.calls, hasLength(1)); // first segment waits
          h.pipeline.cancel();
          h.stt.hold = false;
          h.stt.release();
          settle(async);
          expect(h.stt.calls, hasLength(1));
          expect(h.eventsOf<VoiceTranscribed>(), isEmpty);
          expect(h.tts.spoken, isEmpty);
        });
      },
    );

    test('Fehler im zweiten Segment: VoiceError, kein Text', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(_recording(70, [23, 46]));
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 80));
        h.stt.hold = true;
        h.pipeline.release();
        settle(async);
        h.stt.nextError = StateError('boom');
        h.stt.hold = false;
        h.stt.release();
        settle(async);
        expect(h.eventsOf<VoiceTranscribed>(), isEmpty);
        expect(h.eventsOf<VoiceError>(), hasLength(1));
      });
    });

    test('Halteaufnahme mit niedriger Konfidenz im Folgefenster wird nicht '
        'still verworfen', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
          ),
          transcripts: const [
            Transcript(text: 'Eins', language: 'de', confidence: 0.9),
            Transcript(text: 'Zwei', language: 'de', confidence: 0.4),
          ],
          turns: [ScriptedTurn.text('Erste.'), ScriptedTurn.text('Zweite.')],
        );
        h.pipeline.start();
        async.flushMicrotasks();
        h.fakeAudio.script(
          AudioFrames.pattern('${'.' * 200}${'S' * 10}', frame: frame),
        );
        for (var i = 0; i < 100; i++) {
          async.elapse(const Duration(milliseconds: 100));
          if (h.eventsOf<VoiceListening>().length == 2 &&
              h.pipeline.state == VoiceState.listening) {
            break;
          }
        }
        h.pipeline.hold();
        async.elapse(const Duration(seconds: 10)); // speech after 6 s
        h.pipeline.release();
        async.elapse(const Duration(seconds: 20));
        // 0.4 is below the hands-free threshold 0.5 but a held recording
        // counts as deliberate (0.3): answered, not dropped.
        expect(h.recording.inputs.map((i) => i.text), ['Eins', 'Zwei']);
      });
    });
  });
}
