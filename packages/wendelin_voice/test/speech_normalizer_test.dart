import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

List<String> spoken(String text, String language) =>
    SpokenAnswer.shorten(text, language: language);

void main() {
  // WP41, stage 0: language, input, expected spoken sentences.
  final table = <(String, String, String, List<String>)>[
    // ---- de
    ('de: Doppelpunkt am Satzende', 'de', 'Deine Termine:', ['Deine Termine.']),
    (
      'de: Doppelpunkt vor Kleinschreibung',
      'de',
      'Es gibt zwei Dinge: erstens Milch.',
      ['Es gibt zwei Dinge, erstens Milch.'],
    ),
    (
      'de: Label-Zeile als Satz',
      'de',
      'Ort: Café Mitte\nWann: 10:30',
      ['Ort. Café Mitte', 'Wann. 10 Uhr 30'],
    ),
    (
      'de: volle Stunde',
      'de',
      'Um 10:00 Uhr geht es los.',
      ['Um 10 Uhr geht es los.'],
    ),
    (
      'de: Uhrzeit mit Null',
      'de',
      'Treffen um 09:05.',
      ['Treffen um 9 Uhr 5.'],
    ),
    (
      'de: Abkürzungen',
      'de',
      'Das kostet ca. 5 Euro, z. B. mit Karte, usw.',
      ['Das kostet circa 5 Euro, zum Beispiel mit Karte, und so weiter.'],
    ),
    (
      'de: Pfeile und Emojis',
      'de',
      'Hin → zurück 🎉 fertig ✅.',
      ['Hin zurück fertig.'],
    ),
    (
      'de: Zahl mit Doppelpunkt bleibt',
      'de',
      'Es steht 3:2.',
      ['Es steht 3:2.'],
    ),
    // ---- fr
    (
      'fr: Doppelpunkt mit Leerzeichen',
      'fr',
      'Voici ta liste :',
      ['Voici ta liste.'],
    ),
    (
      'fr: Uhrzeit',
      'fr',
      'Rendez-vous à 14:30.',
      ['Rendez-vous à 14 heures 30.'],
    ),
    ('fr: eine Stunde', 'fr', 'À 01:00 précises.', ['À 1 heure précises.']),
    (
      'fr: Abkürzungen',
      'fr',
      'Il y a env. dix minutes, p. ex. pour un café.',
      ['Il y a environ dix minutes, par exemple pour un café.'],
    ),
    // ---- en
    ('en: colon at the end', 'en', 'Your meetings:', ['Your meetings.']),
    ('en: morning', 'en', 'The call is at 10:00.', ['The call is at 10 a.m.']),
    (
      'en: afternoon',
      'en',
      'Lunch at 15:30 today.',
      ['Lunch at 3:30 p.m. today.'],
    ),
    ('en: midnight', 'en', 'It ends at 00:15.', ['It ends at 12:15 a.m.']),
    (
      'en: abbreviations',
      'en',
      'Bring snacks, e.g. fruit, approx. 5 pieces, etc.',
      ['Bring snacks, for example fruit, approximately 5 pieces, et cetera.'],
    ),
    // ---- unknown language falls back to German
    ('sonst: deutsch', 'it', 'Alle um 08:00', ['Alle um 8 Uhr']),
  ];
  for (final (name, lang, input, expected) in table) {
    test(name, () => expect(spoken(input, lang), expected));
  }

  test('Wörter mit Abkürzungsendung bleiben unverändert', () {
    expect(spoken('Das Plusca. Dann', 'de'), ['Das Plusca.', 'Dann']);
  });
}
