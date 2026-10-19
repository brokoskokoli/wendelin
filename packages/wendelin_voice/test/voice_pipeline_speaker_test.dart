import 'dart:async';
import 'dart:typed_data';

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

    test('erkannte Person: die Id geht mit der Anfrage zum Agenten', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Ok.')],
          speaker: FakeSpeakerRecognizer(anna),
        );
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.single.speakerId, 'a');
      });
    });

    test('unbekannt oder aus: keine Id an den Agenten', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Ok.')],
          speaker: FakeSpeakerRecognizer(
            const SpeakerMatch.unknown(SpeakerUnknownReason.belowThreshold),
          ),
        );
        h.pipeline.start();
        settle(async);
        expect(h.recording.inputs.single.speakerId, isNull);
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

    test('hängende Erkennung: nach dem Zeitlimit unbekannt, Anfrage läuft', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Ok.')],
          speaker: _Hanging(),
        );
        h.pipeline.start();
        async.elapse(VoicePipeline.speakerTimeout * 2);
        async.flushMicrotasks();
        settle(async);
        final t = h.eventsOf<VoiceTranscribed>().single.transcript;
        expect(t.speaker?.reason, SpeakerUnknownReason.failed);
        expect(h.diagnostics, contains('speaker-timeout'));
        expect(h.tts.spoken, ['Ok.']);
      });
    });

    test('Weckwort: Sprecher am Transcript, Anfrage ohne Weckwort', () {
      runFake((async) {
        final h = Harness(
          turns: [ScriptedTurn.text('Ok.')],
          speaker: FakeSpeakerRecognizer(anna),
          transcripts: const [
            Transcript(
              text: 'Wendelin, wie wird das Wetter?',
              language: 'de',
              confidence: 0.9,
            ),
          ],
        );
        h.pipeline.start(
          trigger: TriggerEvent(
            source: TriggerKind.wakeWord,
            at: DateTime.utc(2026, 10, 14),
            preRoll: AudioFrames.speech(const Duration(milliseconds: 600)),
          ),
        );
        settle(async);
        final t = h.eventsOf<VoiceTranscribed>().first.transcript;
        // The event carries the full transcript with the speaker; the agent
        // gets the text without the wake word. (The speaker on the stripped
        // copy is only consumed from WP92b on, so it is not observable yet.)
        expect(t.speaker, anna);
        expect(h.recording.inputs.single.text, 'wie wird das Wetter?');
      });
    });
  });
}

final class _Hanging implements SpeakerRecognizer {
  @override
  Future<SpeakerMatch> identify(Int16List pcm) =>
      Completer<SpeakerMatch>().future;
}
