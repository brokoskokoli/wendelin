import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const frame = Duration(milliseconds: 30);

/// 150 ms silence, 600 ms speech, 900 ms silence (ends after 800 ms).
List<Int16List> utterance() =>
    AudioFrames.pattern('${'.' * 5}${'S' * 20}${'.' * 30}', frame: frame);

String describe(RecognitionEvent e) => switch (e) {
  RecognitionSpeechBegan() => 'began',
  RecognitionSpeechEnded() => 'ended',
  RecognitionResult(:final transcript) => 'result:${transcript.text}',
  RecognitionFailed(:final kind) => 'error:${kind.name}',
};

final class Harness {
  Harness({
    List<Int16List>? frames,
    AudioInput? audio,
    Future<SpeechToText>? stt,
    this.language,
    EndpointConfig endpoint = const EndpointConfig(),
    bool closeAfterFrames = false,
    List<Transcript> transcripts = const [
      Transcript(text: 'Milch kaufen', language: 'de'),
    ],
  }) : fakeAudio = FakeAudioInput(
         frames: frames ?? utterance(),
         closeAfterFrames: closeAfterFrames,
       ),
       fakeStt = FakeSpeechToText(transcripts) {
    session = RecognitionSession(
      audio: audio ?? fakeAudio,
      vad: vad,
      stt: stt ?? Future.value(fakeStt),
      onEvent: (e) => events.add(describe(e)),
      endpoint: endpoint,
      language: language,
    );
  }

  final FakeAudioInput fakeAudio;
  final FakeSpeechToText fakeStt;
  final vad = FakeVoiceActivityDetector();
  final String? language;
  final events = <String>[];
  late final RecognitionSession session;
}

Future<void> until(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue);
}

void main() {
  group('recognitionLanguage', () {
    final cases = <(String?, String?, String?)>[
      (null, 'de', 'de'),
      ('', 'fr', 'fr'),
      ('  ', null, null),
      ('en-US', 'de', 'en'),
      ('fr_FR', 'de', 'fr'),
      ('DE', null, 'de'),
    ];
    for (final (requested, fallback, expected) in cases) {
      test('$requested / $fallback → $expected', () {
        expect(recognitionLanguage(requested, fallback: fallback), expected);
      });
    }

    test('andere Sprache: unsupportedLanguage', () {
      expect(
        () => recognitionLanguage('es-ES', fallback: 'de'),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.unsupportedLanguage,
          ),
        ),
      );
    });
  });

  group('RecognitionSession', () {
    test('Äußerung: Beginn, Ende, Ergebnis; Mikrofon aus', () async {
      final h = Harness(language: 'de');
      await h.session.run();
      expect(h.events, ['began', 'ended', 'result:Milch kaufen']);
      expect(h.fakeAudio.isRunning, isFalse);
      expect(h.fakeAudio.stopCount, 1);
      expect(h.vad.resets, 1);
      expect(h.fakeStt.calls.single.language, 'de');
      // Pre-roll (150 ms) + speech (600 ms) + end silence (≥ 800 ms).
      expect(h.fakeStt.calls.single.samples, durationToSamples(frame * 52));
    });

    test('Endpointing wie die Pipeline: 800 ms Stille beenden', () async {
      // 750 ms silence after speech is not enough, the end needs 800 ms.
      final h = Harness(
        frames: AudioFrames.pattern(
          '${'S' * 10}${'.' * 25}S${'.' * 30}',
          frame: frame,
        ),
      );
      await h.session.run();
      // Speech went on after 750 ms: 10 + 25 + 1 frames, then 800 ms.
      expect(
        h.fakeStt.calls.single.samples,
        durationToSamples(frame * (36 + 27)),
      );
    });

    test('Stille: speechTimeout nach der Wartezeit ohne Sprache', () {
      fakeAsync((async) {
        final h = Harness(
          frames: AudioFrames.pattern('.' * 300, frame: frame),
          endpoint: const EndpointConfig(noSpeechTimeout: Duration(seconds: 3)),
        );
        unawaited(h.session.run());
        async.elapse(const Duration(seconds: 10));
        expect(h.events, ['error:speechTimeout']);
        expect(h.fakeStt.calls, isEmpty);
        expect(h.fakeAudio.isRunning, isFalse);
      });
    });

    test('Sprache, aber leerer Text: noMatch', () async {
      final h = Harness(transcripts: const []);
      await h.session.run();
      expect(h.events, ['began', 'ended', 'error:noMatch']);
    });

    test('Rauschen kürzer als die Mindestsprechdauer: kein Treffer', () {
      fakeAsync((async) {
        final h = Harness(
          frames: AudioFrames.pattern('SS${'.' * 300}', frame: frame),
          endpoint: const EndpointConfig(noSpeechTimeout: Duration(seconds: 2)),
        );
        unawaited(h.session.run());
        async.elapse(const Duration(seconds: 10));
        // The click opened speech briefly, then was dropped as noise.
        expect(h.events, ['began', 'error:speechTimeout']);
      });
    });

    test('stop ohne Sprache: noMatch', () async {
      final h = Harness(frames: AudioFrames.pattern('.....', frame: frame));
      final run = h.session.run();
      await pumpEventQueue();
      h.session.stop();
      await run;
      expect(h.events, ['error:noMatch']);
      expect(h.fakeAudio.isRunning, isFalse);
    });

    test('stop während der Sprache: bisherige Sprache wird erkannt', () async {
      final h = Harness(
        frames: AudioFrames.pattern('SSSSSSSSSS', frame: frame),
      );
      final run = h.session.run();
      await pumpEventQueue();
      h.session.stop();
      await run;
      expect(h.events, ['began', 'ended', 'result:Milch kaufen']);
      // stop after the end is a no-op.
      h.session.stop();
    });

    test('cancel beim Zuhören: keine Ereignisse, Mikrofon aus', () async {
      final h = Harness(frames: AudioFrames.pattern('SSS', frame: frame));
      final run = h.session.run();
      await pumpEventQueue();
      await h.session.cancel();
      await run;
      expect(h.events, ['began']);
      expect(h.session.isCancelled, isTrue);
      expect(h.fakeAudio.isRunning, isFalse);
      await h.session.cancel(); // twice is fine
    });

    test('cancel während der Erkennung: kein Ergebnis', () async {
      final h = Harness()..fakeStt.hold = true;
      final run = h.session.run();
      await until(() => h.fakeStt.calls.isNotEmpty);
      expect(h.events, ['began', 'ended']);
      await h.session.cancel();
      h.fakeStt.release();
      await run;
      expect(h.events, ['began', 'ended']);
    });

    test('cancel während eines Erkennungsfehlers: kein Fehler', () async {
      final h = Harness()
        ..fakeStt.hold = true
        ..fakeStt.nextError = StateError('kaputt');
      final run = h.session.run();
      await until(() => h.fakeStt.calls.isNotEmpty);
      await h.session.cancel();
      h.fakeStt.release();
      await run;
      expect(h.events, ['began', 'ended']);
    });

    final errors = <(String, Object, String)>[
      (
        'Modell fehlt',
        const VoiceException(VoiceErrorKind.modelMissing, 'fehlt'),
        'error:modelMissing',
      ),
      (
        'Sprache',
        const VoiceException(VoiceErrorKind.unsupportedLanguage, 'es'),
        'error:language',
      ),
      (
        'Whisper kaputt',
        const VoiceException(VoiceErrorKind.failed, 'kaputt'),
        'error:client',
      ),
      ('fremder Fehler', StateError('x'), 'error:client'),
    ];
    for (final (name, error, expected) in errors) {
      test('Erkennungsfehler $name → $expected', () async {
        final h = Harness()..fakeStt.nextError = error;
        await h.session.run();
        expect(h.events, ['began', 'ended', expected]);
      });
    }

    test('Whisper lädt nicht: modelMissing nach der Äußerung', () async {
      final h = Harness(
        stt: Future<SpeechToText>.error(
          const VoiceException(VoiceErrorKind.modelMissing, 'fehlt'),
        ),
      );
      await h.session.run();
      expect(h.events, ['began', 'ended', 'error:modelMissing']);
    });

    test('Fehlermeldung kommt aus der VoiceException', () async {
      final messages = <String>[];
      final session = RecognitionSession(
        audio: DeniedAudioInput(),
        vad: FakeVoiceActivityDetector(),
        stt: Future.value(FakeSpeechToText()),
        onEvent: (e) {
          if (e is RecognitionFailed) messages.add(e.message);
        },
      );
      await session.run();
      expect(messages.single, isNotEmpty);
    });

    test('keine Berechtigung beim Start: permission', () async {
      final h = Harness(audio: DeniedAudioInput());
      await h.session.run();
      expect(h.events, ['error:permission']);
    });

    test('Mikrofon fällt aus: audio', () async {
      final h = Harness(frames: AudioFrames.pattern('...', frame: frame));
      final run = h.session.run();
      await pumpEventQueue();
      h.fakeAudio.fail(StateError('weg'));
      await run;
      expect(h.events, ['error:audio']);
      expect(h.fakeAudio.isRunning, isFalse);
    });

    test('Mikrofon endet nach der Sprache: Äußerung wird erkannt', () async {
      final h = Harness(
        frames: AudioFrames.pattern('..SSSSSSSSSS', frame: frame),
        closeAfterFrames: true,
      );
      await h.session.run();
      expect(h.events, ['began', 'ended', 'result:Milch kaufen']);
    });

    test('Mikrofon liefert nichts mehr: Sicherheitsnetz nach der Zeit', () {
      fakeAsync((async) {
        final h = Harness(
          frames: const [],
          endpoint: const EndpointConfig(noSpeechTimeout: Duration(seconds: 1)),
        );
        unawaited(h.session.run());
        async.elapse(const Duration(seconds: 2));
        expect(h.events, isEmpty);
        async.elapse(const Duration(seconds: 2));
        expect(h.events, ['error:speechTimeout']);
      });
    });

    test('Sprache kurz vor dem Sicherheitsnetz wird nicht abgeschnitten', () {
      // The microphone delivers late (wall clock ahead of audio time):
      // speech starts at 9.9 s wall clock, just before the no-speech net
      // (8 s + 2 s); the net must not end the utterance.
      fakeAsync((async) {
        final h = Harness(frames: const []);
        unawaited(h.session.run());
        async.flushMicrotasks();
        for (var i = 0; i < 99; i++) {
          // 100 ms wall clock, but only 70 ms of audio each.
          h.fakeAudio.push(
            AudioFrames.silence(const Duration(milliseconds: 70)),
          );
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(h.events, isEmpty);
        for (var i = 0; i < 10; i++) {
          h.fakeAudio.push(AudioFrames.speech(frame));
          async.elapse(const Duration(milliseconds: 30));
        }
        expect(h.events, ['began']);
        for (var i = 0; i < 30 && h.fakeAudio.isRunning; i++) {
          h.fakeAudio.push(AudioFrames.silence(frame));
          async.elapse(const Duration(milliseconds: 30));
        }
        expect(h.events, ['began', 'ended', 'result:Milch kaufen']);
        // The whole utterance: 300 ms pre-roll, speech, 810 ms silence.
        expect(
          h.fakeStt.calls.single.samples,
          durationToSamples(const Duration(milliseconds: 300) + frame * 37),
        );
      });
    });

    test('Sprache ohne Ende: Höchstdauer, dann Ergebnis', () {
      fakeAsync((async) {
        final h = Harness(
          frames: const [],
          endpoint: const EndpointConfig(maxDuration: Duration(seconds: 3)),
        );
        unawaited(h.session.run());
        async.flushMicrotasks();
        for (var i = 0; i < 20; i++) {
          h.fakeAudio.push(AudioFrames.speech(frame));
        }
        async.flushMicrotasks();
        expect(h.events, ['began']);
        // No more frames arrive: the wall-clock net ends at 3 s + 2 s.
        async.elapse(const Duration(seconds: 6));
        expect(h.events, ['began', 'ended', 'result:Milch kaufen']);
      });
    });

    test('leere Frames werden übersprungen', () async {
      final h = Harness(frames: [Int16List(0), ...utterance()]);
      await h.session.run();
      expect(h.events.last, 'result:Milch kaufen');
    });

    test('zweites run ist ein Fehler', () async {
      final h = Harness();
      await h.session.run();
      expect(h.session.run, throwsStateError);
    });

    test('VAD-Fehler beendet mit audio', () async {
      final session = RecognitionSession(
        audio: FakeAudioInput(frames: utterance()),
        vad: _ThrowingVad(),
        stt: Future.value(FakeSpeechToText()),
        onEvent: (e) => expect(describe(e), 'error:audio'),
      );
      await session.run();
    });

    test('Stopp-Fehler des Mikrofons verdeckt das Ergebnis nicht', () async {
      final events = <String>[];
      final session = RecognitionSession(
        audio: _FailingStopAudio(utterance()),
        vad: FakeVoiceActivityDetector(),
        stt: Future.value(FakeSpeechToText([const Transcript(text: 'Hallo')])),
        onEvent: (e) => events.add(describe(e)),
      );
      await session.run();
      expect(events, ['began', 'ended', 'result:Hallo']);
    });

    test('Ereignistexte', () {
      expect(
        const RecognitionFailed(RecognitionErrorKind.audio, 'x').toString(),
        'RecognitionFailed(audio, x)',
      );
    });
  });
}

final class _ThrowingVad implements VoiceActivityDetector {
  @override
  double get threshold => 0.5;

  @override
  double speechProbability(Int16List frame) => throw StateError('vad');

  @override
  void reset() {}
}

final class _FailingStopAudio implements AudioInput {
  _FailingStopAudio(this.frames);

  final List<Int16List> frames;
  final _c = StreamController<Int16List>();
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Stream<Int16List> start() {
    _running = true;
    scheduleMicrotask(() => frames.forEach(_c.add));
    return _c.stream;
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _c.close();
    throw StateError('stop');
  }
}
