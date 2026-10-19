import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'voice_pipeline_test.dart' show Harness, runFake, settle;

void main() {
  group('Sprechererkennung (WP92a)', () {
    const anna = SpeakerMatch.known(personId: 'a', name: 'Anna', score: 0.8);

    test('aus: kein Aufwand, Transcript ohne Sprecher', () {
      runFake((async) {
        final h = Harness(turns: [ScriptedTurn.text('Ok.')]);
        h.pipeline.start();
        settle(async);
        expect(
          h.eventsOf<VoiceTranscribed>().single.transcript.speaker,
          isNull,
        );
      });
    });

    test('an: Ergebnis hängt am Transcript, Audio ist das der Äußerung', () {
      runFake((async) {
        final rec = FakeSpeakerRecognizer(anna);
        final h = Harness(turns: [ScriptedTurn.text('Ok.')], speaker: rec);
        h.pipeline.start();
        settle(async);
        expect(h.eventsOf<VoiceTranscribed>().single.transcript.speaker, anna);
        expect(rec.lengths, [h.stt.calls.single.samples]);
        expect(h.recording.inputs.single.text, 'Wie wird das Wetter?');
      });
    });

    test('läuft parallel: Erkennung beginnt, solange STT noch läuft', () {
      runFake((async) {
        final rec = FakeSpeakerRecognizer(anna);
        final h = Harness(turns: [ScriptedTurn.text('Ok.')], speaker: rec);
        h.stt.hold = true;
        h.pipeline.start();
        settle(async);
        expect(h.pipeline.state, VoiceState.transcribing);
        expect(rec.lengths, isNotEmpty, reason: 'STT hängt noch');
        expect(h.eventsOf<VoiceTranscribed>(), isEmpty);
        h.stt.release();
        settle(async);
        expect(h.eventsOf<VoiceTranscribed>().single.transcript.speaker, anna);
      });
    });

    test('Fehler der Erkennung: unbekannt, Anfrage läuft weiter', () {
      runFake((async) {
        final rec = FakeSpeakerRecognizer(anna)..throwing = true;
        final h = Harness(turns: [ScriptedTurn.text('Ok.')], speaker: rec);
        h.pipeline.start();
        settle(async);
        final t = h.eventsOf<VoiceTranscribed>().single.transcript;
        expect(t.speaker?.reason, SpeakerUnknownReason.failed);
        expect(h.tts.spoken, ['Ok.']);
        expect(h.diagnostics, contains('speaker-failed'));
      });
    });
  });
}
