import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../src/io/audio_input.dart';
import '../src/io/barge_in_detector.dart';
import '../src/io/speech_to_text.dart';
import '../src/io/text_to_speech.dart';
import '../src/io/voice_activity_detector.dart';
import '../src/io/voice_exception.dart';

/// Creates the implementation under test.
typedef VoiceFactory<T> = FutureOr<T> Function();

Matcher _voiceError(VoiceErrorKind kind) =>
    throwsA(isA<VoiceException>().having((e) => e.kind, 'kind', kind));

/// Contract for every [AudioInput] (platform recorder, `FakeAudioInput`).
///
/// [create] must return an input that delivers at least [minFrames] frames
/// within [timeout] after `start` (on a device: a running microphone).
void audioInputContract(
  VoiceFactory<AudioInput> create, {
  String name = 'AudioInput',
  int minFrames = 3,
  Duration timeout = const Duration(seconds: 5),
}) {
  group('$name erfüllt den AudioInput-Vertrag', () {
    test(
      'liefert nicht-leere Frames bis stop, dann endet der Stream',
      () async {
        final input = await create();
        expect(input.isRunning, isFalse);
        final frames = <Int16List>[];
        final enough = Completer<void>();
        final done = Completer<void>();
        final sub = input.start().listen((f) {
          frames.add(f);
          if (frames.length >= minFrames && !enough.isCompleted) {
            enough.complete();
          }
        }, onDone: done.complete);
        expect(input.isRunning, isTrue);
        await enough.future.timeout(timeout);
        await input.stop();
        await done.future.timeout(timeout);
        expect(input.isRunning, isFalse);
        expect(frames.every((f) => f.isNotEmpty), isTrue);
        await sub.cancel();
      },
    );

    test('start während der Aufnahme wirft StateError', () async {
      final input = await create();
      final sub = input.start().listen((_) {});
      expect(input.start, throwsStateError);
      await input.stop();
      await sub.cancel();
    });

    test(
      'stop ohne Aufnahme ist wirkungslos, Neustart nach stop geht',
      () async {
        final input = await create();
        await input.stop();
        for (var round = 0; round < 2; round++) {
          final first = Completer<void>();
          final sub = input.start().listen((_) {
            if (!first.isCompleted) first.complete();
          });
          await first.future.timeout(timeout);
          await input.stop();
          await sub.cancel();
        }
        expect(input.isRunning, isFalse);
      },
    );
  });
}

/// Contract for every [VoiceActivityDetector].
///
/// With [speechSample] (16 kHz PCM of real speech, cut into frames of
/// [frameSamples]) at least one frame must count as speech.
void voiceActivityDetectorContract(
  VoiceFactory<VoiceActivityDetector> create, {
  String name = 'VoiceActivityDetector',
  Int16List? speechSample,
  int frameSamples = 512,
}) {
  group('$name erfüllt den VAD-Vertrag', () {
    test(
      'Wahrscheinlichkeit liegt in [0, 1], Stille ist keine Sprache',
      () async {
        final vad = await create();
        expect(vad.threshold, inInclusiveRange(0, 1));
        for (var i = 0; i < 20; i++) {
          final p = vad.speechProbability(Int16List(frameSamples));
          expect(p, inInclusiveRange(0, 1));
          expect(p, lessThan(vad.threshold));
        }
      },
    );

    test('reset wirft nie und erlaubt eine neue Aufnahme', () async {
      final vad = await create()
        ..reset()
        ..reset();
      expect(vad.isSpeech(Int16List(frameSamples)), isFalse);
    });

    if (speechSample != null) {
      test('erkennt Sprache in der Probe', () async {
        final vad = await create()
          ..reset();
        var speech = false;
        for (
          var i = 0;
          i + frameSamples <= speechSample.length;
          i += frameSamples
        ) {
          final frame = Int16List.sublistView(
            speechSample,
            i,
            i + frameSamples,
          );
          final p = vad.speechProbability(frame);
          expect(p, inInclusiveRange(0, 1));
          speech = speech || p >= vad.threshold;
        }
        expect(speech, isTrue);
      });
    }
  });
}

/// Contract for every [SpeechToText].
///
/// With [sample] (16 kHz speech) the transcript must contain
/// [expectedText] (case-insensitive) – used with fixtures in WP17.
void speechToTextContract(
  VoiceFactory<SpeechToText> create, {
  String name = 'SpeechToText',
  Int16List? sample,
  String? sampleLanguage,
  String? expectedText,
}) {
  group('$name erfüllt den SpeechToText-Vertrag', () {
    test('Engine-Info nennt Name und Sprachen', () async {
      final stt = await create();
      expect(stt.info.name, isNotEmpty);
      expect(stt.info.languages, isNotEmpty);
    });

    test('Stille liefert leeren, getrimmten Text statt Fehler', () async {
      final stt = await create();
      final t = await stt.transcribe(Int16List(16000));
      expect(t.text.trim(), isEmpty);
      expect(t.text, t.text.trim());
      _checkTranscript(stt, t);
    });

    test('leeres Audio liefert leeren Text', () async {
      final stt = await create();
      final t = await stt.transcribe(Int16List(0));
      expect(t.text, isEmpty);
    });

    test('jede unterstützte Sprache kann fest gesetzt werden', () async {
      final stt = await create();
      for (final lang in stt.info.languages) {
        final t = await stt.transcribe(Int16List(8000), language: lang);
        _checkTranscript(stt, t);
      }
    });

    test(
      'nicht unterstützte Sprache: VoiceException(unsupportedLanguage)',
      () async {
        final stt = await create();
        await expectLater(
          stt.transcribe(Int16List(8000), language: 'xx'),
          _voiceError(VoiceErrorKind.unsupportedLanguage),
        );
      },
    );

    if (sample != null && expectedText != null) {
      test('erkennt die Probe', () async {
        final stt = await create();
        final t = await stt.transcribe(sample, language: sampleLanguage);
        expect(t.text.toLowerCase(), contains(expectedText.toLowerCase()));
        _checkTranscript(stt, t);
      });
    }
  });
}

void _checkTranscript(SpeechToText stt, Transcript t) {
  final c = t.confidence;
  if (c != null) expect(c, inInclusiveRange(0, 1));
  final l = t.language;
  if (l != null) expect(stt.info.languages, contains(l));
}

/// Contract for every [TextToSpeech].
///
/// [create] must return an available engine. [utterance] is spoken once in
/// full (keep it short on a device).
void textToSpeechContract(
  VoiceFactory<TextToSpeech> create, {
  String name = 'TextToSpeech',
  String utterance = 'Test.',
  Duration timeout = const Duration(seconds: 10),
}) {
  group('$name erfüllt den TextToSpeech-Vertrag', () {
    test('ist verfügbar und nennt Stimmen mit Sprache', () async {
      final tts = await create();
      expect(await tts.isAvailable, isTrue);
      for (final v in await tts.voices()) {
        expect(v.id, isNotEmpty);
        expect(v.language, isNotEmpty);
      }
    });

    test('speak: speaking während der Ausgabe, danach idle', () async {
      final tts = await create();
      final states = <TtsState>[];
      final sub = tts.states.listen(states.add);
      expect(tts.state, TtsState.idle);
      await tts.speak(utterance).timeout(timeout);
      expect(tts.state, TtsState.idle);
      expect(states, containsAllInOrder([TtsState.speaking, TtsState.idle]));
      await sub.cancel();
    });

    test('stop beendet die Ausgabe, speak-Future endet', () async {
      final tts = await create();
      final speaking = tts.states.firstWhere((s) => s == TtsState.speaking);
      final done = tts.speak('$utterance $utterance $utterance');
      await speaking.timeout(timeout);
      await tts.stop();
      await done.timeout(timeout);
      expect(tts.state, TtsState.idle);
    });

    test('stop ohne Ausgabe ist wirkungslos und idempotent', () async {
      final tts = await create();
      await tts.stop();
      await tts.stop();
      expect(tts.state, TtsState.idle);
    });

    test('leerer Text endet sofort ohne Ausgabe', () async {
      final tts = await create();
      final states = <TtsState>[];
      final sub = tts.states.listen(states.add);
      await tts.speak('   ').timeout(timeout);
      expect(states, isEmpty);
      await sub.cancel();
    });

    test('rate <= 0 wirft ArgumentError', () async {
      final tts = await create();
      expect(() => tts.speak(utterance, rate: 0), throwsArgumentError);
    });
  });
}

/// Contract of every [BargeInDetector].
///
/// [fire] makes the detector under test deliver [signal] (for a fake: its
/// `emit`; on a device: a played keyword). A detector is idle until
/// [BargeInDetector.start], start and stop are idempotent, and nothing is
/// delivered while stopped.
void bargeInDetectorContract(
  VoiceFactory<BargeInDetector> create, {
  required FutureOr<void> Function(BargeInDetector detector, BargeInSignal s)
  fire,
  String name = 'BargeInDetector',
}) {
  group('$name erfüllt den BargeInDetector-Vertrag', () {
    test('ist zunächst aus; start und stop sind idempotent', () async {
      final d = await create();
      expect(d.isRunning, isFalse);
      await d.start();
      await d.start();
      expect(d.isRunning, isTrue);
      await d.stop();
      await d.stop();
      expect(d.isRunning, isFalse);
    });

    test('stop während start aussteht: danach aus', () async {
      final d = await create();
      final starting = d.start();
      await d.stop();
      await starting;
      await d.stop();
      expect(d.isRunning, isFalse);
    });

    test('liefert Signale nur während des Laufs', () async {
      final d = await create();
      final got = <BargeInSignal>[];
      final sub = d.signals.listen(got.add);
      await fire(d, const BargeInSignal.keyword(BargeInKeyword.stop));
      await Future<void>.delayed(Duration.zero);
      expect(got, isEmpty);
      await d.start();
      await fire(d, const BargeInSignal.keyword(BargeInKeyword.wake));
      await Future<void>.delayed(Duration.zero);
      expect(got.map((s) => s.code), ['keyword-wake']);
      await d.stop();
      await fire(d, const BargeInSignal.speech());
      await Future<void>.delayed(Duration.zero);
      expect(got, hasLength(1));
      await sub.cancel();
    });
  });
}
