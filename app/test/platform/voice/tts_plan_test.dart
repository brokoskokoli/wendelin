// Sprecher-/Ladeplan der Offline-Stimme und Dateisuche (WP103, Nachbesserung).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';

void main() {
  group('planTtsVoice', () {
    test('Kokoro: sid und espeak-Sprache aus dem Katalog', () {
      final heart = planTtsVoice('tts-kokoro/af_heart');
      expect(heart.sid, 3);
      expect(heart.espeakLang, 'en-us');
      final emma = planTtsVoice('tts-kokoro/bf_emma');
      expect(emma.sid, 21);
      expect(emma.espeakLang, 'en');
      final siwis = planTtsVoice('tts-kokoro/ff_siwis');
      expect(siwis.sid, 30);
      expect(siwis.espeakLang, 'fr');
      expect(siwis.modelId, 'tts-kokoro');
    });

    test('Neuladen je Sprache, nicht je Sprecher', () {
      String key(String id) => planTtsVoice(id).loadKey;
      // en-us und en sind verschiedene Phonemizer-Sprachen: neu laden.
      expect(key('tts-kokoro/af_heart'), isNot(key('tts-kokoro/bf_emma')));
      expect(key('tts-kokoro/af_heart'), isNot(key('tts-kokoro/ff_siwis')));
      expect(key('tts-kokoro/af_heart'), key('tts-kokoro/af_heart'));
      expect(key('tts-kokoro/af_heart'), isNot('tts-kokoro/af_heart'));
      expect(key('tts-kokoro/ff_siwis'), 'tts-kokoro@fr');
    });

    test('Piper und unbekannter Sprecher: sid 0, keine Sprache', () {
      final piper = planTtsVoice('tts-de-thorsten');
      expect(piper.loadKey, 'tts-de-thorsten');
      expect(piper.sid, 0);
      expect(piper.espeakLang, isNull);
      final unknown = planTtsVoice('tts-kokoro/gibt_es_nicht');
      expect(unknown.sid, 0);
      expect(unknown.espeakLang, isNull);
    });
  });

  group('PiperVoiceFiles.find mit Katalogart', () {
    Directory voice({required bool voices}) {
      final tmp = Directory.systemTemp.createTempSync('voice');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/m.onnx').writeAsStringSync('x');
      File('${tmp.path}/tokens.txt').writeAsStringSync('x');
      Directory('${tmp.path}/espeak-ng-data').createSync();
      if (voices) File('${tmp.path}/voices.bin').writeAsStringSync('x');
      return tmp;
    }

    test('Kokoro im Katalog ohne voices.bin: nicht nutzbar', () {
      expect(PiperVoiceFiles.find(voice(voices: false), kokoro: true), isNull);
    });

    test('Kokoro mit voices.bin: voicesBin gesetzt', () {
      final d = voice(voices: true);
      expect(
        PiperVoiceFiles.find(d, kokoro: true)!.voicesBin,
        '${d.path}/voices.bin',
      );
    });

    test('Piper im Katalog ignoriert eine fremde voices.bin', () {
      expect(
        PiperVoiceFiles.find(voice(voices: true), kokoro: false)!.voicesBin,
        isNull,
      );
    });
  });
}
