import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/whisper_sherpa.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'ffi_support.dart';

/// Whisper stand-in: answers with [text]/[language] and records calls.
final class FakeWhisperBackend implements WhisperBackend {
  FakeWhisperBackend({this.text = 'Schreib Milch und Brot', this.language});

  String text;
  String? language;
  Object? error;
  final calls = <(int, String?)>[];

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    calls.add((samples.length, language));
    final e = error;
    if (e != null) throw e;
    return WhisperResult(
      text: text,
      language: this.language ?? language ?? 'de',
    );
  }

  @override
  Future<void> dispose() async {}
}

Matcher _kind(VoiceErrorKind k) =>
    throwsA(isA<VoiceException>().having((e) => e.kind, 'kind', k));

void main() {
  final speech = fixture('de-03').samples;

  speechToTextContract(
    () => WhisperSpeechToText(
      backend: FakeWhisperBackend(),
      modelId: 'whisper-base',
    ),
    name: 'WhisperSpeechToText (Attrappe)',
    sample: speech,
    sampleLanguage: 'de',
    expectedText: 'milch und brot',
  );

  group('WhisperSpeechToText', () {
    test('Info nennt Modell und Sprachen', () {
      final stt = WhisperSpeechToText(
        backend: FakeWhisperBackend(),
        modelId: 'whisper-small',
      );
      expect(stt.info.model, 'whisper-small');
      expect(stt.info.languages, {'de', 'fr', 'en'});
      expect(stt.info.name, contains('Whisper'));
    });

    test('Stille läuft nicht durchs Modell', () async {
      final b = FakeWhisperBackend(text: '[Music]');
      final stt = WhisperSpeechToText(backend: b, modelId: 'm');
      final quiet = Int16List.fromList(List.filled(16000, 20));
      expect((await stt.transcribe(quiet)).text, '');
      expect(b.calls, isEmpty);
    });

    test('feste Sprache wird weitergegeben, Regionsteil entfernt', () async {
      final b = FakeWhisperBackend(language: 'it');
      final stt = WhisperSpeechToText(backend: b, modelId: 'm');
      final t = await stt.transcribe(speech, language: 'fr-CH');
      expect(b.calls.single.$2, 'fr');
      expect(t.language, 'fr');
      await expectLater(
        stt.transcribe(speech, language: 'it'),
        _kind(VoiceErrorKind.unsupportedLanguage),
      );
    });

    test('automatisch: erkannte Sprache außerhalb de/fr/en wird null, '
        'Konfidenz sinkt', () async {
      final b = FakeWhisperBackend(
        text: 'Buongiorno a tutti voi',
        language: 'it',
      );
      final stt = WhisperSpeechToText(backend: b, modelId: 'm');
      final t = await stt.transcribe(speech);
      expect(b.calls.single.$2, isNull);
      expect(t.language, isNull);
      expect(t.confidence, lessThan(0.5));
      b
        ..language = 'en'
        ..text = 'Add milk';
      final en = await stt.transcribe(speech);
      expect(en.language, 'en');
      expect(en.confidence, 0.9);
    });

    test('Halluzination ergibt leeren Text ohne Konfidenz', () async {
      final b = FakeWhisperBackend(text: 'Untertitel der Amara.org-Community');
      final stt = WhisperSpeechToText(backend: b, modelId: 'm');
      final t = await stt.transcribe(speech, language: 'de');
      expect(t.text, '');
      expect(t.confidence, isNull);
      expect(t.language, 'de');
    });

    test('Fehler des Modells: VoiceException(failed)', () async {
      final b = FakeWhisperBackend()..error = StateError('boom');
      final stt = WhisperSpeechToText(backend: b, modelId: 'm');
      await expectLater(stt.transcribe(speech), _kind(VoiceErrorKind.failed));
    });
  });

  group('cleanWhisperText', () {
    for (final (raw, clean) in [
      ('  Hallo   Welt ', 'Hallo Welt'),
      ('[Music]', ''),
      ('(Lachen) Ja, gerne.', 'Ja, gerne.'),
      ('*Musik* ♪ Stopp ♪', 'Stopp'),
      ('...', ''),
      ('Untertitelung des ZDF, 2020', ''),
      ('Sous-titrage Société Radio-Canada', ''),
      ('Thanks for watching!', ''),
      ('Vielen Dank fürs Zuschauen.', ''),
      ("Merci d'avoir regardé.", ''),
      ('Vielen Dank für die Info', 'Vielen Dank für die Info'),
      ('Untertitel im Auftrag des ZDF, 2021', ''),
      ('Untertitel für den Film suchen', 'Untertitel für den Film suchen'),
      ("Sous-titres réalisés par la communauté d'Amara.org", ''),
      ('Sous-titres en français activés', 'Sous-titres en français activés'),
    ]) {
      test('„$raw“', () => expect(cleanWhisperText(raw), clean));
    }
  });

  group('whisperConfidence', () {
    const second = Duration(seconds: 2);
    test('normaler Satz', () {
      expect(whisperConfidence('Trag mir Tauchen ein', audio: second), 0.9);
    });
    test('zu wenig Text für lange Aufnahme', () {
      expect(
        whisperConfidence('Ja', audio: const Duration(seconds: 4)),
        closeTo(0.54, 1e-9),
      );
    });
    test('kurze Antwort mit Pre-Roll und Endstille ist unverdächtig', () {
      expect(
        whisperConfidence('Ja', audio: const Duration(milliseconds: 500)),
        0.9,
      );
      expect(
        whisperConfidence('Ja.', audio: const Duration(milliseconds: 1900)),
        0.9,
      );
      expect(
        whisperConfidence(
          'Ja',
          audio: const Duration(seconds: 2, milliseconds: 999),
        ),
        0.9,
      );
    });
    test('zu viel Text', () {
      expect(whisperConfidence('x' * 70, audio: second), closeTo(0.45, 1e-9));
    });
    test('Wiederholungen', () {
      expect(
        whisperConfidence('nein nein nein nein, gut', audio: second),
        closeTo(0.36, 1e-9),
      );
      expect(
        whisperConfidence(
          'ich bin da und ich bin da und ich bin da',
          audio: const Duration(seconds: 3),
        ),
        closeTo(0.36, 1e-9),
      );
      expect(whisperConfidence('nein nein nein gut', audio: second), 0.9);
    });
  });

  test('abgeschnittene Modelldatei: modelMissing vor dem Laden', () async {
    final tmp = Directory.systemTemp.createTempSync('whisper');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const model = SpeechModelCatalog.whisperBase;
    for (final f in model.files) {
      File('${tmp.path}/${f.name}').writeAsBytesSync([1, 2, 3]);
    }
    final files = WhisperFiles.of(model, tmp.path);
    expect(files.sizes[files.encoder], 29120534);
    await expectLater(
      IsolateWhisperBackend.start(files),
      _kind(VoiceErrorKind.modelMissing),
    );
  });

  test('WhisperFiles.of wählt Encoder, Decoder, Tokens', () {
    final f = WhisperFiles.of(SpeechModelCatalog.whisperSmall, '/m');
    expect(f.encoder, '/m/small-encoder.int8.onnx');
    expect(f.decoder, '/m/small-decoder.int8.onnx');
    expect(f.tokens, '/m/small-tokens.txt');
    expect(primaryLanguage(' DE-at '), 'de');
  });
}
