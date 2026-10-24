import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  group('matchesHeyWakeWord (WP142)', () {
    test('Treffer: Vorwort direkt vor dem Wake-Word', () {
      for (final t in [
        'Hey Wendelin',
        'hey, Wendelin!',
        'Hei Wendelin',
        'Hi Wendlin',
        'Ok, hey Wendelin, wie spät ist es',
        'Hey Wende Lin',
        'Hey Vendelin',
      ]) {
        expect(matchesHeyWakeWord(t), isTrue, reason: t);
      }
    });

    test('kein Treffer: ohne Vorwort, anderes Wort, nur Vorwort, leer', () {
      for (final t in [
        'Wendelin.',
        'Wendelin',
        'Hey Octavia',
        'Hey',
        'Hey Alexa',
        'Hey du, Wendelin',
        'Wendelin hey',
        'Hallo Wendelin',
        'Hey Wendel in den Keller',
        '',
        '   ',
      ]) {
        expect(matchesHeyWakeWord(t), isFalse, reason: t);
        expect(matchesHeyWakeWord(t, lenient: true), isFalse, reason: t);
      }
    });

    test('lenient nimmt Fehlhörungen von „Hey“ dazu, strict nicht', () {
      for (final t in [
        'a Wendelin',
        'Äh Wendelin',
        'Yeah Wendelin',
        'Nee Wendelin',
        'ja Wendelin',
        'and Wendelin',
        'E Wendelin',
        'ne Wendelin',
        'ah Wendelin',
      ]) {
        expect(matchesHeyWakeWord(t), isFalse, reason: t);
        expect(matchesHeyWakeWord(t, lenient: true), isTrue, reason: t);
      }
    });

    test('die Wortlisten', () {
      expect(heyWords, {
        'hey',
        'hei',
        'he',
        'hej',
        'hay',
        'ey',
        'eh',
        'ei',
        'hi',
      });
      expect(heyWordsLenient.difference(heyWords), {
        'a',
        'ah',
        'äh',
        'e',
        'yeah',
        'nee',
        'ne',
        'ja',
        'and',
      });
    });
  });

  group('TranscriptWakeVerifier.hear', () {
    Future<HeardWake> hear(String text) =>
        TranscriptWakeVerifier(FixedTranscriptStt(text)).hear(Int16List(1600));

    test('drei Ausgänge', () async {
      expect(await hear('Hey Wendelin'), HeardWake.heyWendelin);
      expect(await hear('äh Wendelin'), HeardWake.heyWendelin);
      expect(await hear('Wendelin'), HeardWake.wendelinOnly);
      expect(await hear('Hey Octavia'), HeardWake.other);
      expect(await hear(''), HeardWake.other);
    });

    test(
      'confirm bleibt unverändert (Stufe 2): Wendelin allein genügt',
      () async {
        final v = TranscriptWakeVerifier(FixedTranscriptStt('Wendelin'));
        expect(await v.confirm(Int16List(1600)), isTrue);
      },
    );
  });
}
