import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/wer.dart';

import 'ffi_support.dart';

void main() {
  group('PcmBytesDecoder', () {
    test('little-endian, Vorzeichen, Byte über Chunk-Grenzen', () {
      final d = PcmBytesDecoder();
      // 1, -2, 0x1234 split as [01 00 FE] [FF 34 12]
      expect(d.convert([0x01, 0x00, 0xfe]), [1]);
      expect(d.convert([0xff, 0x34, 0x12]), [-2, 0x1234]);
      expect(d.convert([0x00]), isEmpty);
      expect(d.convert([0x80]), [-32768]);
    });

    test('leerer Chunk nach ungeradem Chunk behält den Übertrag', () {
      final d = PcmBytesDecoder();
      expect(d.convert([0x34]), isEmpty);
      expect(d.convert([]), isEmpty);
      expect(d.convert([0x12, 0x01, 0x00]), [0x1234, 1]);
      expect(d.convert([]), isEmpty);
      expect(d.convert([0x02, 0x00]), [2]);
    });
  });

  test('float/pcm hin und zurück, rmsLevel', () {
    final pcm = Int16List.fromList([0, 16384, -16384, 32767, -32768]);
    final f = pcmToFloat(pcm);
    expect(f[1], 0.5);
    expect(f[4], -1);
    expect(floatToPcm(Float32List.fromList([0, 0.5, -0.5, 2, -2])), [
      0,
      16384,
      -16384,
      32767,
      -32768,
    ]);
    expect(rmsLevel(Int16List(0)), 0);
    expect(rmsLevel(Int16List.fromList([16384, -16384])), 0.5);
  });

  group('Wav', () {
    test('encode/parse hin und zurück', () {
      final wav = Wav(Int16List.fromList([1, -1, 300]), sampleRate: 22050);
      final back = Wav.parse(wav.encode());
      expect(back.samples, [1, -1, 300]);
      expect(back.sampleRate, 22050);
      expect(Wav(Int16List(16000)).duration, const Duration(seconds: 1));
    });

    test('Fixture: 16 kHz mono, unbekannte Abschnitte werden übersprungen', () {
      final w = fixture('de-11');
      expect(w.sampleRate, 16000);
      expect(w.samples, isNotEmpty);
      final raw = Wav(Int16List.fromList([5, 6])).encode();
      final withList = Uint8List.fromList([
        ...raw.sublist(0, 36),
        ...'LIST'.codeUnits, 3, 0, 0, 0, 1, 2, 3, 0, // odd chunk + pad
        ...raw.sublist(36),
      ]);
      expect(Wav.parse(withList).samples, [5, 6]);
    });

    test('falsche Formate', () {
      expect(() => Wav.parse(Uint8List(4)), throwsFormatException);
      final stereo = Wav(Int16List(2)).encode()..[22] = 2;
      expect(() => Wav.parse(stereo), throwsFormatException);
      final noData = Wav(Int16List(0)).encode().sublist(0, 36);
      expect(() => Wav.parse(noData), throwsFormatException);
    });
  });

  group('WER', () {
    test('Wörter: Satzzeichen, Apostroph, Bindestrich, Zahlen', () {
      expect(werWords('Trag mir um 10 Uhr ein.', 'de'), [
        'trag',
        'mir',
        'um',
        'zehn',
        'uhr',
        'ein',
      ]);
      expect(werWords("Rappelle-moi d'appeler", 'fr'), [
        'rappelle',
        'moi',
        'd',
        'appeler',
      ]);
      expect(werWords('à 7h30, à 9h00', 'fr'), [
        'à',
        'sept',
        'heures',
        '30',
        'à',
        'neuf',
        'heures',
      ]);
      expect(werWords('17 and 99', 'en'), ['seventeen', 'and', '99']);
      expect(werWords('17', 'fr'), ['dix', 'sept']);
      expect(werWords('3', 'xx'), ['3']);
    });

    test('Edit-Distanz', () {
      expect(wordErrors('a b c', 'a b c', 'en'), (errors: 0, words: 3));
      expect(wordErrors('a b c', 'a x c', 'en'), (errors: 1, words: 3));
      expect(wordErrors('a b c', 'a c', 'en'), (errors: 1, words: 3));
      expect(wordErrors('a b', 'a b c d', 'en'), (errors: 2, words: 2));
      expect(wordErrors('a b', '', 'en'), (errors: 2, words: 2));
    });

    test('Zähler', () {
      final c = WerCounter()
        ..add((errors: 1, words: 4))
        ..add((errors: 0, words: 4));
      final all = WerCounter()..merge(c);
      expect(all.rate, 0.125);
      expect(all.percent, '12,5 %');
      expect(all.exact, 1);
      expect(all.sentences, 2);
      expect(WerCounter().rate, 0);
    });
  });
}
