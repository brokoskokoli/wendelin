import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

/// Feeds [text] in pieces of [size] characters and flushes.
List<String> chunk(String text, int size) {
  final c = SentenceChunker();
  final out = <String>[];
  for (var i = 0; i < text.length; i += size) {
    out.addAll(c.add(text.substring(i, (i + size).clamp(0, text.length))));
  }
  return out..addAll(c.flush());
}

void main() {
  const cases = <(String, String, List<String>)>[
    // de
    (
      'de: zwei Sätze',
      'Hallo Stefan. Wie geht es dir?',
      ['Hallo Stefan.', 'Wie geht es dir?'],
    ),
    (
      'de: z. B. mit Leerzeichen',
      'Nimm z. B. Äpfel. Dann Birnen.',
      ['Nimm z. B. Äpfel.', 'Dann Birnen.'],
    ),
    (
      'de: z.B. ohne Leerzeichen',
      'Etwa z.B. Tauchen. Gut so.',
      ['Etwa z.B. Tauchen.', 'Gut so.'],
    ),
    (
      'de: Dr.',
      'Termin bei Dr. Müller ist morgen. Passt das?',
      ['Termin bei Dr. Müller ist morgen.', 'Passt das?'],
    ),
    (
      'de: Uhrzeit 10.30 Uhr',
      'Der Termin ist um 10.30 Uhr. Soll ich ihn eintragen?',
      ['Der Termin ist um 10.30 Uhr.', 'Soll ich ihn eintragen?'],
    ),
    (
      'de: Uhrzeit am Satzende',
      'Treffen um 10.30. Danach Mittag.',
      ['Treffen um 10.30.', 'Danach Mittag.'],
    ),
    (
      'de: Ordinalzahl vor Monat',
      'Am 3. Oktober ist frei. Gut.',
      ['Am 3. Oktober ist frei.', 'Gut.'],
    ),
    (
      'de: Zahl am Satzende',
      'Es sind 5. Das reicht.',
      ['Es sind 5.', 'Das reicht.'],
    ),
    (
      'de: Anführungszeichen',
      'Er sagte: „Komm mit.“ Dann ging er.',
      ['Er sagte: „Komm mit.“', 'Dann ging er.'],
    ),
    (
      'de: Nr. und bzw.',
      'Ruf Nr. 5 an bzw. schreib ihm. Fertig!',
      ['Ruf Nr. 5 an bzw. schreib ihm.', 'Fertig!'],
    ),
    (
      'de: Kleinbuchstabe nach Punkt',
      'Das gilt ca. ab morgen. Okay.',
      ['Das gilt ca. ab morgen.', 'Okay.'],
    ),
    (
      'de: Zeilenumbruch',
      'Einkaufsliste\nMilch\nBrot',
      ['Einkaufsliste', 'Milch', 'Brot'],
    ),
    (
      'de: Auslassungspunkte',
      'Moment... Ich schaue nach. Erledigt.',
      ['Moment...', 'Ich schaue nach.', 'Erledigt.'],
    ),
    (
      'de: ?! und Rest ohne Punkt',
      'Wirklich?! Dann mache ich das',
      ['Wirklich?!', 'Dann mache ich das'],
    ),
    // fr
    (
      'fr: Leerzeichen vor ? und !',
      'Vraiment ? Oui, bien sûr ! Allons-y.',
      ['Vraiment ?', 'Oui, bien sûr !', 'Allons-y.'],
    ),
    (
      'fr: M. und Mme',
      'M. Dupont et Mme. Martin arrivent. Bonne journée.',
      ['M. Dupont et Mme. Martin arrivent.', 'Bonne journée.'],
    ),
    (
      'fr: Guillemets',
      'Il a dit « Bonjour. » Puis il est parti.',
      ['Il a dit « Bonjour. »', 'Puis il est parti.'],
    ),
    (
      'fr: p. ex.',
      'Prends p. ex. des pommes. Merci.',
      ['Prends p. ex. des pommes.', 'Merci.'],
    ),
    // en
    (
      'en: e.g. and Mr.',
      'Ask Mr. Smith, e.g. tomorrow. Thanks!',
      ['Ask Mr. Smith, e.g. tomorrow.', 'Thanks!'],
    ),
    (
      'en: decimal number',
      'It costs 3.50 dollars. Buy it?',
      ['It costs 3.50 dollars.', 'Buy it?'],
    ),
    (
      'en: initials',
      'J. R. R. Tolkien wrote it. Nice.',
      ['J. R. R. Tolkien wrote it.', 'Nice.'],
    ),
    (
      'en: quoted question',
      '"Really?" she asked. Yes.',
      ['"Really?" she asked.', 'Yes.'],
    ),
    (
      'en: ellipsis character',
      'Well… Let me check.',
      ['Well…', 'Let me check.'],
    ),
    (
      'en: ellipsis after a single letter',
      'Then plan B... Okay.',
      ['Then plan B...', 'Okay.'],
    ),
    ('empty input', '', <String>[]),
    ('only whitespace', '  \n ', <String>[]),
  ];

  group('SentenceChunker', () {
    for (final (name, text, expected) in cases) {
      test(name, () {
        expect(chunk(text, text.length + 1), expected, reason: 'in one piece');
        expect(chunk(text, 1), expected, reason: 'char by char');
        expect(chunk(text, 3), expected, reason: 'in pieces of 3');
      });
    }

    test('returns a sentence only once the next one has started', () {
      final c = SentenceChunker();
      expect(c.add('Hallo Stefan.'), isEmpty);
      expect(c.add(' '), isEmpty);
      expect(c.add('Wie'), ['Hallo Stefan.']);
      expect(c.pending, 'Wie');
      expect(c.flush(), ['Wie']);
      expect(c.pending, isEmpty);
    });

    test('reset drops pending text', () {
      final c = SentenceChunker()..add('Ich kann das nicht');
      c.reset();
      expect(c.flush(), isEmpty);
    });

    test('custom abbreviations replace the defaults', () {
      final c = SentenceChunker(abbreviations: {'abc'});
      expect(c.add('Siehe Abc. Test. Dr. Who. '), ['Siehe Abc. Test.', 'Dr.']);
      expect(c.flush(), ['Who.']);
    });
  });
}
