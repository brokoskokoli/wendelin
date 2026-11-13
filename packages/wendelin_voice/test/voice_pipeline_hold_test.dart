import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart' show ScriptedTurn;
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, frame, runFake, settle;

void main() {
  group('Haltemodus / Push-to-Talk (WP192)', () {
    // 300 ms speech, 3 s silence, 300 ms speech: 3.6 s = 120 frames of 30 ms.
    final long = AudioFrames.pattern(
      '${'S' * 10}${'.' * 100}${'S' * 10}',
      frame: frame,
    );

    test('Halten mit 3 s Pause: eine Äußerung mit allem Audio, erst Loslassen '
        'beendet', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(long);
        expect(h.pipeline.start(hold: true), isTrue);
        async.elapse(const Duration(seconds: 10)); // all frames long played
        expect(h.pipeline.state, VoiceState.listening);
        expect(h.stt.calls, isEmpty);
        h.pipeline.release();
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(h.stt.calls.single.samples, greaterThanOrEqualTo(120 * 480));
        expect(h.recording.inputs, hasLength(1));
        expect(h.tts.spoken, ['Ja.']);
        expect(h.eventsOf<VoiceHoldLimitReached>(), isEmpty);
      });
    });

    test('hold() während des Zuhörens (nach Sprache) verhindert das Ende', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(long);
        h.pipeline.start();
        async.elapse(const Duration(milliseconds: 600));
        h.pipeline.hold();
        async.elapse(const Duration(seconds: 10));
        expect(h.pipeline.state, VoiceState.listening);
        h.pipeline.release();
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(h.stt.calls.single.samples, greaterThanOrEqualTo(120 * 480));
      });
    });

    test('ohne hold endet dasselbe Audio nach 800 ms Stille (unverändert)', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(long);
        h.pipeline.start();
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(h.stt.calls.single.samples, lessThan(60 * 480));
      });
    });

    test('Halten im Folgefenster: das Fenster läuft nicht ab, Loslassen '
        'verarbeitet', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
          ),
          transcripts: const [
            Transcript(text: 'Eins'),
            Transcript(text: 'Zwei'),
          ],
          turns: [ScriptedTurn.text('Erste.'), ScriptedTurn.text('Zweite.')],
        );
        h.pipeline.start();
        async.flushMicrotasks();
        h.fakeAudio.script(
          AudioFrames.pattern('${'.' * 200}${'S' * 10}', frame: frame),
        );
        // Run until the follow-up window is listening.
        for (var i = 0; i < 100; i++) {
          async.elapse(const Duration(milliseconds: 100));
          final l = h.eventsOf<VoiceListening>();
          if (l.length == 2 && h.pipeline.state == VoiceState.listening) break;
        }
        expect(h.eventsOf<VoiceListening>().last.followUp, isTrue);
        h.pipeline.hold();
        async.elapse(const Duration(seconds: 10)); // window is 1 s
        expect(h.pipeline.state, VoiceState.listening);
        expect(h.recording.inputs, hasLength(1));
        h.pipeline.release();
        async.elapse(const Duration(seconds: 3));
        expect(h.recording.inputs.map((i) => i.text), ['Eins', 'Zwei']);
      });
    });

    test(
      'Obergrenze: nach holdMaxDuration wird verarbeitet, Event meldet es',
      () {
        runFake((async) {
          final h = Harness(
            config: const VoicePipelineConfig(
              endpoint: EndpointConfig(holdMaxDuration: Duration(seconds: 3)),
            ),
            turns: [ScriptedTurn.text('Ja.')],
          );
          h.fakeAudio.script(
            AudioFrames.pattern('${'S' * 10}${'.' * 1000}', frame: frame),
          );
          h.pipeline.start(hold: true);
          async.elapse(const Duration(seconds: 2));
          expect(h.pipeline.state, VoiceState.listening);
          settle(async);
          expect(h.eventsOf<VoiceHoldLimitReached>(), hasLength(1));
          expect(h.stt.calls, hasLength(1));
          expect(h.tts.spoken, ['Ja.']);
        });
      },
    );

    test('Obergrenze greift auch, wenn das Mikrofon keine Frames mehr '
        'liefert (Wanduhr)', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            endpoint: EndpointConfig(holdMaxDuration: Duration(seconds: 3)),
          ),
          turns: [ScriptedTurn.text('Ja.')],
        );
        h.fakeAudio.script(AudioFrames.pattern('S' * 10, frame: frame));
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 2));
        expect(h.stt.calls, isEmpty);
        settle(async);
        expect(h.eventsOf<VoiceHoldLimitReached>(), hasLength(1));
        expect(h.stt.calls, hasLength(1));
      });
    });

    test('Wanduhr: Halten ohne Frames überlebt die normale Maximaldauer '
        '(30 s) und endet an der Obergrenze (2 min)', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(AudioFrames.pattern('S' * 10, frame: frame));
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 90));
        expect(h.pipeline.state, VoiceState.listening);
        expect(h.stt.calls, isEmpty);
        async.elapse(const Duration(seconds: 60));
        expect(h.eventsOf<VoiceHoldLimitReached>(), hasLength(1));
        expect(h.stt.calls, hasLength(1));
      });
    });

    test('Rennen: hold/release ohne Zuhören und doppeltes release sind '
        'wirkungslos', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.pipeline
          ..hold() // idle
          ..release();
        h.fakeAudio.script(long);
        h.pipeline.start(); // normal endpointing: no hold from before
        settle(async);
        expect(h.stt.calls.single.samples, lessThan(60 * 480));
        h.pipeline
          ..release() // after the end
          ..hold(); // idle again
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('Rennen: release vor Mikrofonstart beendet das Zuhören ohne '
        'Aufnahme', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(long);
        h.pipeline.start(hold: true);
        h.pipeline.release();
        settle(async);
        expect(h.stt.calls, isEmpty);
        expect(h.eventsOf<VoiceNothingUnderstood>(), hasLength(1));
        expect(h.pipeline.state, VoiceState.idle);
      });
    });

    test('ein Halten gilt nur für ein Zuhören: das nächste endet normal', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('A.'), ScriptedTurn.text('B.')],
        );
        h.fakeAudio.script(long);
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 5));
        h.pipeline.release();
        settle(async);
        h.fakeAudio.script(long);
        h.pipeline.start();
        settle(async);
        expect(h.stt.calls, hasLength(2));
        expect(h.stt.calls.last.samples, lessThan(60 * 480));
      });
    });

    test('Abbruch nach vorzeitigem release hinterlässt kein Loslassen für das '
        'nächste Halten', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ja.')]);
        h.fakeAudio.script(long);
        h.pipeline.start(hold: true);
        h.pipeline.release(); // before the microphone exists
        h.pipeline.cancel();
        settle(async);
        h.fakeAudio.script(long);
        expect(h.pipeline.start(hold: true), isTrue);
        async.elapse(const Duration(seconds: 10));
        expect(h.pipeline.state, VoiceState.listening);
        expect(h.eventsOf<VoiceNothingUnderstood>(), isEmpty);
        h.pipeline.release();
        settle(async);
        expect(h.stt.calls, hasLength(1));
        expect(h.stt.calls.single.samples, greaterThanOrEqualTo(120 * 480));
      });
    });

    test('Gesprächsmodus: das Halten endet mit der ersten Runde, das '
        'Folgefenster läuft normal ab', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
          ),
          transcripts: const [Transcript(text: 'Eins')],
          turns: [ScriptedTurn.text('Erste.')],
        );
        h.fakeAudio.script(long);
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 5));
        h.pipeline.release();
        // Answer, then the follow-up window (1 s, no speech) must expire.
        async.elapse(const Duration(seconds: 20));
        expect(h.recording.inputs.map((i) => i.text), ['Eins']);
        expect(h.pipeline.state, VoiceState.idle);
        expect(h.eventsOf<VoiceListening>().last.followUp, isTrue);
      });
    });

    test('Gesprächsmodus: nach der Obergrenze läuft das Folgefenster normal '
        'ab (kein Halten über die Runde hinaus)', () {
      runFake((async) {
        final h = Harness(
          config: const VoicePipelineConfig(
            conversationMode: true,
            followUpWindow: Duration(seconds: 1),
            endpoint: EndpointConfig(holdMaxDuration: Duration(seconds: 3)),
          ),
          transcripts: const [Transcript(text: 'Eins')],
          turns: [ScriptedTurn.text('Erste.')],
        );
        h.fakeAudio.script(
          AudioFrames.pattern('${'S' * 10}${'.' * 1000}', frame: frame),
        );
        h.pipeline.start(hold: true);
        async.elapse(const Duration(seconds: 30)); // nobody releases
        expect(h.eventsOf<VoiceHoldLimitReached>(), hasLength(1));
        expect(h.recording.inputs.map((i) => i.text), ['Eins']);
        expect(h.eventsOf<VoiceListening>().last.followUp, isTrue);
        expect(h.pipeline.state, VoiceState.idle);
      });
    });
  });
}
