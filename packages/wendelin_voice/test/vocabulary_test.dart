import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// A realistic vault (18 names): the assistant name, note titles and list
/// names like on the device in the test of 2026-10-13 (B6). Single-word
/// titles are dropped by [Vocabulary] but listed here on purpose.
final _vocabulary = Vocabulary(
  const [
    'Wendelin-Test',
    'Garten',
    'Rezepte',
    'Geschenke',
    'Courses',
    'Einkaufen',
    'Einkaufsliste',
    'Urlaub Ideen',
    'Projekt Phoenix',
    'Tagesnotiz',
    'Journal',
    'Lesezeichen',
    'Reise Mallorca',
    'Shopping',
    'Recettes',
    'Gift Ideas',
    'Home Office',
  ],
  names: const ['Wendelin'],
);

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
      ('Wändelin, stopp', 'Wendelin, stopp'),
      ('Vendelin hilf mir', 'Wendelin hilf mir'),
      ('Wendel in, hörst du?', 'Wendelin, hörst du?'),
      ('Wendolin', 'Wendelin'),
      // Mehrwortiger Titel.
      ('Lies Projekt Phönix vor', 'Lies Projekt Phoenix vor'),
      ('Reise Malorka planen', 'Reise Mallorca planen'),
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
        fix('Vendelin, lies Wandel Intest'),
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
      // Review WP33: Alltagssätze, die früher falsch korrigiert wurden.
      'Leg die Karten auf den Tisch.',
      'Ich koche heute ein Rezept.',
      'Mein Geschenk ist fertig.',
      'The garden hose is broken.',
      // Weitere Alltagssätze (de/fr/en) gegen das Vokabular oben.
      'Ich brauche eine Urlaub Idee.',
      'Die Reise nach Mallorca war schön.',
      'Die Gärten blühen schon.',
      'Wendelins Notiz ist lang.',
      'Hallo Wendeline, wie spät ist es?',
      'Der Projektplan ist fertig.',
      'Wir gehen morgen einkaufen.',
      'Schreib das ins Journal.',
      'Lies mir die Lesezeichen vor.',
      'Ich war gestern shoppen.',
      'Je fais les courses demain.',
      "Une recette de gâteau, s'il te plaît.",
      'Le journal de bord est plein.',
      'I need some gift ideas for mom.',
      'We work from the home office today.',
      'Add eggs to the shopping list.',
      // Ältere Fälle.
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

    test('zwei gleich gute Kandidaten: keiner wird genommen', () {
      // Allein wird „Maier Hof“ zu „Mayer Hof“ korrigiert …
      expect(
        fix('Maier Hof lesen', vocabulary: Vocabulary(['Mayer Hof'])),
        'Mayer Hof lesen',
      );
      // … mit „Meier Hof“ (ebenfalls 1 Edit, gleicher Schlüssel) nicht.
      expect(
        fix(
          'Maier Hof lesen',
          vocabulary: Vocabulary(['Mayer Hof', 'Meier Hof']),
        ),
        'Maier Hof lesen',
      );
    });

    test('Stoppwort am Rand eines unscharfen Laufs', () {
      final v = Vocabulary(['Imkerei Plan']);
      // Ohne Stoppwort: 1 Edit, gleicher Schlüssel → korrigiert.
      expect(fix('Der Imkerey Plan', vocabulary: v), 'Der Imkerei Plan');
      // „im Kerey Plan“ hätte als Lauf „imkereyplan“ (1 Edit) – aber
      // beginnt mit dem Stoppwort „im“.
      expect(fix('Der im Kerey Plan', vocabulary: v), 'Der im Kerey Plan');
      // Nur anders getrennt (0 Edits) darf auch am Stoppwort liegen.
      expect(fix('Der im Kerei Plan', vocabulary: v), 'Der Imkerei Plan');
    });

    test('nur die Endung unterscheidet sich', () {
      for (final (a, b, only) in [
        ('rezept', 'rezepte', true),
        ('geschenke', 'geschenk', true),
        ('urlaubidee', 'urlaubideen', true),
        ('urlaubiden', 'urlaubideen', true),
        ('wendelins', 'wendelin', true),
        ('karten', 'garten', false),
        ('wandelintest', 'wendelintest', false),
        ('projektphonix', 'projektphoenix', false),
      ]) {
        expect(VocabularyCorrector.onlyEndingDiffers(a, b), only, reason: a);
      }
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

    test('leeres Vokabular', () {
      expect(
        fix('Wandel Intest', vocabulary: Vocabulary.empty),
        'Wandel Intest',
      );
    });
  });

  group('Vokabular', () {
    test('verwirft kurze, einwortige und doppelte Titel, Stoppwörter', () {
      final v = Vocabulary(
        [
          'Test',
          ' Notiz ',
          'Notizen',
          'Garten',
          'Wendelin-Test',
          'wendelin test',
          'Wendelin',
          '',
        ],
        names: ['Wendelin', 'Heinz'],
      );
      expect(v.terms.map((t) => t.text), ['Wendelin', 'Wendelin-Test']);
      expect(v.terms.map((t) => t.name), [true, false]);
      expect(v.terms.last.words, 2);
      expect(v.isEmpty, isFalse);
      expect(Vocabulary.empty.isEmpty, isTrue);
    });

    test('toString nennt keine Namen (Datenschutz)', () {
      expect(_vocabulary.toString(), isNot(contains('Wendelin')));
      expect(_vocabulary.toString(), contains('7'));
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

    test('Sprache wird durchgereicht und wählt den Schlüssel (M18)', () async {
      // „Kesar“/„Cesar“: Kölner Phonetik (de) verschieden (4… / 8…), der
      // einfache Schlüssel (fr/en) gleich.
      final v = Vocabulary(['Cesar Plan']);
      Future<(String, String?)> run(Transcript t, String? language) async {
        final inner = FakeSpeechToText([t]);
        final stt = CorrectingSpeechToText(inner, vocabulary: () => v);
        final out = await stt.transcribe(_speech(), language: language);
        return (out.text, inner.calls.single.language);
      }

      expect(await run(const Transcript(text: 'Kesar Plan'), 'de'), (
        'Kesar Plan',
        'de',
      ));
      expect(await run(const Transcript(text: 'Kesar Plan'), 'fr'), (
        'Cesar Plan',
        'fr',
      ));
      // Die erkannte Sprache des Ergebnisses geht vor.
      expect(
        await run(const Transcript(text: 'Kesar Plan', language: 'en'), 'de'),
        ('Cesar Plan', 'de'),
      );
      expect(
        await run(const Transcript(text: 'Kesar Plan', language: 'de'), null),
        ('Kesar Plan', null),
      );
    });

    test('meldet die eingesetzten Namen, auch leer', () async {
      final inner = FakeSpeechToText([
        const Transcript(text: 'Lies Wandel Intest', language: 'de'),
        const Transcript(text: 'Hallo', language: 'de'),
      ]);
      final reported = <List<String>>[];
      final stt = CorrectingSpeechToText(
        inner,
        vocabulary: () => _vocabulary,
        onCorrected: (terms) => reported.add([for (final t in terms) t.text]),
      );
      await stt.transcribe(_speech());
      await stt.transcribe(_speech());
      await stt.transcribe(Int16List(1600));
      expect(reported, [
        ['Wendelin-Test'],
        <String>[],
        <String>[],
      ]);
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
