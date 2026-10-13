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
      'Ort: Café Mitte\nWann: um 10:30',
      ['Ort. Café Mitte', 'Wann, um 10 Uhr 30'],
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
    // ---- en: 12-hour handling
    ('en: noon half past', 'en', 'Lunch at 12:30.', ['Lunch at 12:30 p.m.']),
    ('en: noon', 'en', 'Lunch at 12:00.', ['Lunch at 12 p.m.']),
    (
      'en: p.m. stays',
      'en',
      'Call at 10:00 p.m. sharp',
      ['Call at 10:00 p.m. sharp'],
    ),
    ('en: pm stays', 'en', 'Call at 10:30 pm', ['Call at 10:30 pm']),
    ('en: PM stays', 'en', 'Call at 10:30 PM.', ['Call at 10:30 PM.']),
    ('en: am stays', 'en', 'Wake at 6:15 am', ['Wake at 6:15 am']),
    (
      'en: a.m. stays',
      'en',
      'From 09:00 a.m. to 5:00 p.m.',
      ['From 09:00 a.m. to 5:00 p.m.'],
    ),
    // ---- no clock times
    (
      'de: Verhältnis',
      'de',
      'Der Maßstab ist 1:25.',
      ['Der Maßstab ist 1:25.'],
    ),
    (
      'de: Verhältnis zweistellig',
      'de',
      'Mischung 10:30 Wasser.',
      ['Mischung 10:30 Wasser.'],
    ),
    (
      'de: Bibelstelle',
      'de',
      'Johannes 3:16 sagt es.',
      ['Johannes 3:16 sagt es.'],
    ),
    (
      'de: Spielstand',
      'de',
      'Es steht 12:10 nach der Pause.',
      ['Es steht 12:10 nach der Pause.'],
    ),
    ('de: ab mit Uhr', 'de', 'Ab 18:30 Uhr offen.', ['Ab 18 Uhr 30 offen.']),
    ('de: bis', 'de', 'Offen bis 17:45.', ['Offen bis 17 Uhr 45.']),
    (
      'de: führende Null ohne Wort',
      'de',
      'Start 09:30 morgen.',
      ['Start 9 Uhr 30 morgen.'],
    ),
    (
      'de: am ist keine Marke',
      'de',
      'um 10:30 am Dienstag',
      ['um 10 Uhr 30 am Dienstag'],
    ),
    (
      'fr: jusqu\'à',
      'fr',
      'Ouvert jusqu\'à 17:45.',
      ['Ouvert jusqu\'à 17 heures 45.'],
    ),
    ('fr: ratio', 'fr', 'Echelle 1:25.', ['Echelle 1:25.']),
    ('en: ratio', 'en', 'Scale is 10:30 here.', ['Scale is 10:30 here.']),
    (
      'en: from/until',
      'en',
      'Open from 09:00 until 17:30.',
      ['Open from 9 a.m. until 5:30 p.m.'],
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
