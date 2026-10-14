import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  audioInputContract(
    () => FakeAudioInput(frames: AudioFrames.pattern('S.S.S.S.')),
    name: 'FakeAudioInput',
  );
  voiceActivityDetectorContract(
    FakeVoiceActivityDetector.new,
    name: 'FakeVoiceActivityDetector',
    speechSample: AudioFrames.speech(const Duration(milliseconds: 200)),
  );
  speechToTextContract(
    () => FakeSpeechToText([const Transcript(text: 'Hallo Welt')]),
    name: 'FakeSpeechToText',
    sample: AudioFrames.speech(),
    sampleLanguage: 'de',
    expectedText: 'hallo',
  );
  modelStoreContract(FakeModelStore.new, name: 'FakeModelStore');
  bargeInDetectorContract(
    FakeBargeInDetector.new,
    name: 'FakeBargeInDetector',
    fire: (d, s) => (d as FakeBargeInDetector).emit(s),
  );

  group('FakeAudioInput', () {
    test('push, fail und selbst endender Stream', () async {
      final input = FakeAudioInput(closeAfterFrames: true);
      final frames = <Int16List>[];
      final errors = <Object>[];
      final done = Completer<void>();
      input.start().listen(
        frames.add,
        onError: errors.add,
        onDone: done.complete,
      );
      input
        ..push(AudioFrames.silence())
        ..fail(StateError('Mikro weg'));
      await done.future;
      expect(frames, hasLength(1));
      expect(errors, hasLength(1));
      expect(input.isRunning, isFalse);
      expect(() => input.push(AudioFrames.silence()), throwsStateError);
    });

    test('script ersetzt die Frames für den nächsten Start', () async {
      final input = FakeAudioInput()..script(AudioFrames.pattern('SS'));
      final frames = await input.start().take(2).toList();
      expect(frames, hasLength(2));
      await input.stop();
      expect(input.startCount, 1);
      expect(input.stopCount, 1);
      expect(input.deliveredFrames, 2);
    });

    test(
      'startError wird geworfen; DeniedAudioInput meldet fehlende Berechtigung',
      () async {
        final input = FakeAudioInput(startError: StateError('x'));
        expect(input.start, throwsStateError);
        final denied = DeniedAudioInput();
        expect(denied.isRunning, isFalse);
        expect(
          denied.start,
          throwsA(
            isA<VoiceException>().having(
              (e) => e.kind,
              'kind',
              VoiceErrorKind.permissionDenied,
            ),
          ),
        );
        await denied.stop();
      },
    );
  });

  group('FakeSpeechToText', () {
    test('Skript, Fehler und Halten', () async {
      final stt = FakeSpeechToText([const Transcript(text: 'Eins')])
        ..nextError = StateError('kaputt');
      final speech = AudioFrames.speech();
      await expectLater(stt.transcribe(speech), throwsStateError);
      stt.hold = true;
      final pending = stt.transcribe(speech, language: 'fr');
      var done = false;
      unawaited(pending.then((_) => done = true));
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      stt.release();
      expect((await pending).text, 'Eins');
      stt.hold = false;
      expect((await stt.transcribe(speech)).text, isEmpty); // script empty
      stt.enqueue(const Transcript(text: 'Zwei'));
      expect((await stt.transcribe(speech)).text, 'Zwei');
      expect(stt.calls.map((c) => c.language), [null, 'fr', null, null]);
    });
  });

  group('FakeVoiceActivityDetector', () {
    test('leere Frames sind keine Sprache, reset wird gezählt', () {
      final vad = FakeVoiceActivityDetector()..reset();
      expect(vad.speechProbability(Int16List(0)), 0);
      expect(vad.isSpeech(AudioFrames.speech()), isTrue);
      expect(vad.resets, 1);
      expect(vad.frames, 2);
    });
  });

  group('Wertobjekte', () {
    test('Transcript und TtsVoice vergleichen nach Wert', () {
      const a = Transcript(text: 'x', language: 'de', confidence: 0.5);
      expect(a, const Transcript(text: 'x', language: 'de', confidence: 0.5));
      expect(
        a.hashCode,
        const Transcript(text: 'x', language: 'de', confidence: 0.5).hashCode,
      );
      expect(a, isNot(const Transcript(text: 'y')));
      expect(a.toString(), contains('x'));
      const v = TtsVoice(id: 'a', language: 'de', name: 'A');
      expect(v, const TtsVoice(id: 'a', language: 'de'));
      expect(v.hashCode, const TtsVoice(id: 'a', language: 'de').hashCode);
      expect(v.toString(), contains('a'));
      const info = SpeechToTextEngineInfo(name: 'n', languages: {'de'});
      expect(info.toString(), contains('n'));
      const err = VoiceException(VoiceErrorKind.failed, 'x');
      expect(err.toString(), contains('failed'));
    });

    test('Umrechnung Samples ↔ Dauer bei 16 kHz', () {
      expect(samplesToDuration(16000), const Duration(seconds: 1));
      expect(durationToSamples(const Duration(milliseconds: 30)), 480);
    });
  });
}
