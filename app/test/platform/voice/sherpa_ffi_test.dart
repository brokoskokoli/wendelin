// Desktop-FFI-Tests mit echten Modellen (macOS, sherpa_onnx_macos):
//
//   WENDELIN_MODELS=/pfad/zu/modellen flutter test test/platform/voice/sherpa_ffi_test.dart
//
// <modelle>/whisper-base, silero-vad, tts-de-thorsten (entpackt) wie im
// ModelStore. Ohne WENDELIN_MODELS werden die Tests übersprungen.
@Tags(['platform-sensitive'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';
import 'package:wendelin/platform/voice/silero_vad.dart';
import 'package:wendelin/platform/voice/whisper_share.dart';
import 'package:wendelin/platform/voice/whisper_sherpa.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'ffi_support.dart';

void main() {
  final skip = ffiSkip;
  if (skip == null) useDesktopSherpa();
  final dir = modelsDir ?? '';
  final padded = Int16List(4800 + fixture('de-03').samples.length + 12800)
    ..setRange(
      4800,
      4800 + fixture('de-03').samples.length,
      fixture('de-03').samples,
    );

  group('Desktop-FFI', skip: skip, () {
    IsolateWhisperBackend? backend;
    tearDownAll(() async => backend?.dispose());

    Future<SpeechToText> whisper() async {
      backend ??= await IsolateWhisperBackend.start(
        WhisperFiles.of(SpeechModelCatalog.whisperBase, '$dir/whisper-base'),
      );
      return WhisperSpeechToText(backend: backend!, modelId: 'whisper-base');
    }

    speechToTextContract(
      whisper,
      name: 'Whisper base (Isolat)',
      sample: padded,
      sampleLanguage: 'de',
      expectedText: 'milch und brot',
    );

    voiceActivityDetectorContract(
      () => SileroVoiceActivityDetector(
        modelPath: '$dir/silero-vad/silero_vad.onnx',
      ),
      name: 'Silero VAD',
      speechSample: fixture('en-01').samples,
    );

    test('Silero erkennt „Ja“, aber kein Grundrauschen', () {
      final vad = SileroVoiceActivityDetector(
        modelPath: '$dir/silero-vad/silero_vad.onnx',
      );
      addTearDown(vad.dispose);
      bool anySpeech(Int16List pcm) {
        vad.reset();
        var any = false;
        for (var i = 0; i + 320 <= pcm.length; i += 320) {
          any = vad.isSpeech(Int16List.sublistView(pcm, i, i + 320)) || any;
        }
        return any;
      }

      expect(anySpeech(fixture('de-11').samples), isTrue);
      final noise = Int16List.fromList([
        for (var i = 0; i < 32000; i++) (i * 7919 % 113) - 56,
      ]);
      expect(anySpeech(noise), isFalse);
    });

    test(
      'Whisper-Isolat beantwortet auch geteilte Anfragen (ADR 0008)',
      () async {
        await whisper();
        final remote = WhisperSpeechToText(
          backend: RemoteWhisperBackend(backend!.sharePort),
          modelId: 'whisper-base',
        );
        final t = await remote.transcribe(padded, language: 'de');
        expect(t.text.toLowerCase(), contains('milch und brot'));
        // The owner keeps working afterwards.
        final own = await (await whisper()).transcribe(padded, language: 'de');
        expect(own.text.toLowerCase(), contains('milch und brot'));
      },
    );

    test('Whisper mit fester Sprache, Abbau des Isolats', () async {
      final b = await IsolateWhisperBackend.start(
        WhisperFiles.of(SpeechModelCatalog.whisperBase, '$dir/whisper-base'),
        threads: 2,
      );
      final r = await b.transcribe(pcmToFloat(padded), language: 'de');
      expect(r.language, 'de');
      expect(r.text.toLowerCase(), contains('brot'));
      await b.dispose();
      await b.worker.exited;
      expect(b.worker.killed, isFalse, reason: 'selbst beendet');
      await b.dispose();
      expect(() => b.transcribe(Float32List(10)), throwsStateError);
    });

    test('fehlende Modelldatei: VoiceException(modelMissing)', () async {
      await expectLater(
        IsolateWhisperBackend.start(
          const WhisperFiles(encoder: '/nix', decoder: '/nix', tokens: '/nix'),
        ),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.modelMissing,
          ),
        ),
      );
    });

    // A broken model file is not testable here: sherpa-onnx ends the whole
    // process (native exit) instead of returning an error. Protection is
    // the SHA-256 check of every download (ModelDownloader).

    final voiceDir = Directory(
      '$dir/tts-de-thorsten/vits-piper-de_DE-thorsten-medium-int8',
    );
    test(
      'Piper-Stimme synthetisiert im Isolat',
      skip: voiceDir.existsSync() ? false : 'Stimme nicht entpackt',
      () async {
        final files = PiperVoiceFiles.find(voiceDir)!;
        final synth = IsolateSherpaSynthesizer(
          () async => {'tts-de-thorsten': files},
        );
        final wav = await synth.synthesize(
          'Hallo, ich bin Wendelin.',
          voiceId: 'tts-de-thorsten',
        );
        expect(wav.sampleRate, 22050);
        expect(wav.duration, greaterThan(const Duration(milliseconds: 800)));
        expect(rmsLevel(wav.samples), greaterThan(0.01));
        final worker = await synth.worker!;
        await synth.dispose();
        await worker.exited;
        expect(worker.killed, isFalse, reason: 'selbst beendet');
      },
    );
  });
}
