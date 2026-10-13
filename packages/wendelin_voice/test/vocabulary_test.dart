import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Names like on the device in the test of 2026-10-13 (B6).
final _vocabulary = Vocabulary([
  'Wendelin',
  'Wendelin-Test',
  'Einkaufen',
  'Urlaub Ideen',
  'Projekt Phoenix',
]);

Int16List _speech() => Int16List.fromList(List.filled(1600, 900));

void main() {
  const corrector = VocabularyCorrector();
  String fix(String text, {Vocabulary? vocabulary, String? language}) =>
      corrector.correct(text, vocabulary ?? _vocabulary, language: language);

  group('Korrektur', () {
    for (final (heard, expected) in [
      // B6 auf dem Gerät mit whisper-base.
      (
        'Was steht in meiner Notiz Wandel Intest?',
        'Was steht in meiner Notiz Wendelin-Test?',
      ),
      (
        'Ergänze in Wendeline Test den Status.',
        'Ergänze in Wendelin-Test den Status.',
      ),
      ('Wandel Intest', 'Wendelin-Test'),
      // Synthetische Stimme mit base: Name an „Notiz“ geklebt.
      (
        'Was steht in meiner Notizwende-Lintest?',
        'Was steht in meiner Notiz Wendelin-Test?',
      ),
      ('Notizwandelintest', 'Notiz Wendelin-Test'),
      ('Wendelintest lesen', 'Wendelin-Test lesen'),
      // Varianten des Assistentennamens.
      ('Hallo Wendeline, wie spät ist es?', 'Hallo Wendelin, wie spät ist es?'),
      ('Wändelin, stopp', 'Wendelin, stopp'),
      ('Vendelin hilf mir', 'Wendelin hilf mir'),
      ('Wendel in, hörst du?', 'Wendelin, hörst du?'),
      ('Wendolin', 'Wendelin'),
      // Mehrwortiger Titel.
      ('Lies Urlaub Iden vor', 'Lies Urlaub Ideen vor'),
      // Französisch und Englisch mit dem einfachen Schlüssel.
      ('Lis la note Wandel Intest', 'Lis la note Wendelin-Test'),
    ]) {
      test(
        '„$heard“ → „$expected“',
        () => expect(
          fix(heard, language: heard.startsWith('Lis ') ? 'fr' : 'de'),
          expected,
        ),
      );
    }

    test('mehrere Namen in einem Satz', () {
      expect(
        fix('Wendeline, lies Wandel Intest'),
        'Wendelin, lies Wendelin-Test',
      );
    });

    test('Englisch', () {
      expect(
        fix('Read my note Wandel Intest please', language: 'en'),
        'Read my note Wendelin-Test please',
      );
    });
  });

  group('bleibt unverändert', () {
    for (final text in [
      // Gewöhnliche Wörter und Beugungen.
      'Ich muss heute einkaufen.',
      'Wir haben gestern eingekauft.',
      'Wie wird das Wetter heute in Berlin?',
      'Trag mir morgen um zehn Uhr Tauchen ein.',
      'Schreib Milch und Brot auf die Einkaufsliste.',
      'Lies mir die letzte Notiz vor.',
      'Wandel ist wichtig.',
      'Die Notizenliste ist lang.',
      'Notizwender-Lintest',
      // Schon richtig.
      'Was steht in Wendelin-Test?',
      'Was steht in Wendelin Test?',
      'Hallo Wendelin',
      // Zu kurz, nur Stoppwörter, leer.
      'Ja.',
      'in der',
      '',
    ]) {
      test('„$text“', () => expect(fix(text), text));
    }

    test('zwei gleich gute Kandidaten', () {
      final v = Vocabulary(['Mayer-Notiz', 'Meier-Notiz']);
      expect(fix('Maier Notiz lesen', vocabulary: v), 'Maier Notiz lesen');
    });

    test('kein phonetisch passender Name trotz kleiner Distanz', () {
      // „Wendelin-Text“: 1 Zeichen, aber anderer Schlüssel (x ≠ s).
      expect(
        fix('Wendelin Text', vocabulary: Vocabulary(['Wendelin-Test'])),
        'Wendelin Text',
      );
    });

    test('zu weit entfernt', () {
      expect(fix('Wandelein Intester'), 'Wandelein Intester');
    });

    test('Stoppwort am Rand wird nicht verschluckt', () {
      // „in Wendelin“ hätte als Lauf die Buchstaben „inwendelin“.
      expect(fix('Was steht in Wendelin'), 'Was steht in Wendelin');
    });

    test('leeres Vokabular', () {
      expect(
        fix('Wandel Intest', vocabulary: Vocabulary.empty),
        'Wandel Intest',
      );
    });
  });

  group('Vokabular', () {
    test('verwirft kurze Namen, Stoppwörter und Doppelte', () {
      final v = Vocabulary([
        'Test',
        ' Notiz ',
        'Notizen',
        'Wendelin-Test',
        'wendelin test',
        '',
      ]);
      expect(v.terms.map((t) => t.text), ['Wendelin-Test']);
      expect(v.terms.single.words, 2);
      expect(v.isEmpty, isFalse);
      expect(Vocabulary.empty.isEmpty, isTrue);
    });

    test('toString nennt keine Namen (Datenschutz)', () {
      expect(_vocabulary.toString(), isNot(contains('Wendelin')));
      expect(_vocabulary.toString(), contains('5'));
    });

    test('Grenzwerte der Distanz', () {
      expect(VocabularyCorrector.maxDistance(6), 1);
      expect(VocabularyCorrector.maxDistance(9), 1);
      expect(VocabularyCorrector.maxDistance(10), 2);
    });
  });

  group('CorrectingSpeechToText', () {
    test('korrigiert mit dem aktuellen Vokabular, ohne Log', () async {
      final inner = FakeSpeechToText([
        const Transcript(
          text: 'Was steht in Wandel Intest?',
          language: 'de',
          confidence: 0.6,
        ),
        const Transcript(text: 'Wandel Intest', language: 'de'),
      ]);
      var vocabulary = _vocabulary;
      final stt = CorrectingSpeechToText(inner, vocabulary: () => vocabulary);
      final printed = <String>[];
      final t = await runZoned(
        () => stt.transcribe(_speech(), language: 'de'),
        zoneSpecification: ZoneSpecification(
          print: (_, _, _, line) => printed.add(line),
        ),
      );
      expect(
        t,
        const Transcript(
          text: 'Was steht in Wendelin-Test?',
          language: 'de',
          confidence: 0.6,
        ),
      );
      expect(printed, isEmpty);
      expect(stt.info, inner.info);

      vocabulary = Vocabulary.empty;
      expect(
        (await stt.transcribe(_speech(), language: 'de')).text,
        'Wandel Intest',
      );
    });

    test('lässt leere und unveränderte Ergebnisse durch', () async {
      const same = Transcript(text: 'Hallo Wendelin', language: 'de');
      final inner = FakeSpeechToText([same]);
      var asked = 0;
      final stt = CorrectingSpeechToText(
        inner,
        vocabulary: () async {
          asked++;
          return _vocabulary;
        },
      );
      expect(await stt.transcribe(Int16List(1600)), isA<Transcript>());
      expect(asked, 0, reason: 'Stille: kein Vokabular nötig');
      expect(identical(await stt.transcribe(_speech()), same), isTrue);
      expect(asked, 1);
    });

    test(
      'nutzt die Sprache des Aufrufs, wenn das Ergebnis keine hat',
      () async {
        final inner = FakeSpeechToText([
          const Transcript(text: 'Read Wandel Intest'),
        ]);
        final stt = CorrectingSpeechToText(
          inner,
          vocabulary: () => _vocabulary,
        );
        expect(
          (await stt.transcribe(_speech(), language: 'en')).text,
          'Read Wendelin-Test',
        );
      },
    );
  });

  speechToTextContract(
    () => CorrectingSpeechToText(
      FakeSpeechToText([const Transcript(text: 'Hallo', language: 'de')]),
      vocabulary: () => _vocabulary,
    ),
    name: 'CorrectingSpeechToText',
  );
}
