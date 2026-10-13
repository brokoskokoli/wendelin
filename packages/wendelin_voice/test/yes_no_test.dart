import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  const recognizer = YesNoRecognizer();

  // Tabelle: Transkript → erwartete Antwort (null = nicht eindeutig, Tipp).
  const cases = <(String, YesNo?)>[
    // de – ja
    ('Ja', YesNo.yes),
    ('ja.', YesNo.yes),
    ('Ja, bitte!', YesNo.yes),
    ('Jawohl', YesNo.yes),
    ('Ja, lösch ihn.', YesNo.yes),
    ('Genau', YesNo.yes),
    ('Okay', YesNo.yes),
    ('OK, mach das', YesNo.yes),
    ('Na klar', YesNo.yes),
    ('In Ordnung', YesNo.yes),
    ('Ja ja', YesNo.yes),
    // de – nein
    ('Nein', YesNo.no),
    ('nein danke', YesNo.no),
    ('Nee', YesNo.no),
    ('Nö.', YesNo.no),
    ('Lieber nicht', YesNo.no),
    ('Auf keinen Fall', YesNo.no),
    ('Nicht löschen', YesNo.no),
    ('Stopp', YesNo.no),
    ('Abbrechen', YesNo.no),
    ('Lass es', YesNo.no),
    // fr – oui
    ('Oui', YesNo.yes),
    ('Oui, vas-y', YesNo.yes),
    ("D'accord", YesNo.yes),
    ('D’accord.', YesNo.yes),
    ('Bien sûr', YesNo.yes),
    ('Ouais', YesNo.yes),
    ("C'est bon", YesNo.yes),
    // fr – non
    ('Non', YesNo.no),
    ('Non merci', YesNo.no),
    ('Surtout pas', YesNo.no),
    ('Annule', YesNo.no),
    ('Pas du tout', YesNo.no),
    ('Laisse tomber', YesNo.no),
    // en – yes
    ('Yes', YesNo.yes),
    ('Yes please', YesNo.yes),
    ('Yeah', YesNo.yes),
    ('Sure', YesNo.yes),
    ('Go ahead', YesNo.yes),
    ('Do it.', YesNo.yes),
    // en – no
    ('No', YesNo.no),
    ('Nope', YesNo.no),
    ("No, don't", YesNo.no),
    ("Don't do it", YesNo.no),
    ('Cancel', YesNo.no),
    ('Never', YesNo.no),
    // unklar → Tipp
    ('', null),
    ('   ', null),
    ('Vielleicht', null),
    ('Jein', null),
    ('Ja, nein', null),
    ('Ja, aber nicht jetzt', YesNo.no),
    ('Mach das nicht', null),
    ('Oui non', null),
    ('Peut-être', null),
    ('Maybe', null),
    ('Yes, no', null),
    ('Pas de problème oui', null),
    ('Trag mir morgen um zehn Tauchen ein und ja', null),
    // Review WP18: schwache Ja-Wörter nur allein, Zögern nie Ja.
    ('Klar', YesNo.yes),
    ('Klar, bitte', YesNo.yes),
    ('Passt', YesNo.yes),
    ('Mach', YesNo.yes),
    ('Richtig', YesNo.yes),
    ('Na ja', null),
    ('Naja', null),
    ('Mach das später', null),
    ('Mach mal Pause', null),
    ('Okay, warte', null),
    ('Ja, Moment', null),
    ('Ja, warte mal', null),
    ('Yes, wait', null),
    ('Yes but later', null),
    ('Hold on', null),
    ('Oui mais attends', null),
    ('Oui, plus tard', null),
    ('Klar ist das falsch', YesNo.no),
    ('Richtig blöd', null),
    ('Passt schon irgendwie', null),
    ('Nein, warte', YesNo.no),
    ('Moment', null),
    ('Attends', null),
  ];

  // Strenge Zustimmung (external, Eskalation): 1–2 reine Ja-Wörter oder
  // eine Ja-Wendung; „nein“ wie sonst.
  const strictCases = <(String, YesNo?)>[
    ('Ja', YesNo.yes),
    ('Ja.', YesNo.yes),
    ('Ja ja', YesNo.yes),
    ('Ja genau', YesNo.yes),
    ('Okay', YesNo.yes),
    ('Oui', YesNo.yes),
    ("D'accord", YesNo.yes),
    ('Bien sûr', YesNo.yes),
    ('Yes', YesNo.yes),
    ('Go ahead', YesNo.yes),
    ('Klar', YesNo.yes),
    ('Ja, bitte', null),
    ('Ja, lösch ihn.', null),
    ('OK, mach das', null),
    ('Oui, vas-y', null),
    ('Yes please', null),
    ('Ja ja ja', null),
    ('Klar, bitte', null),
    ('Nein', YesNo.no),
    ('Non merci', YesNo.no),
    ("No, don't", YesNo.no),
    ('Lieber nicht', YesNo.no),
    ('Ja, Moment', null),
    ('Vielleicht', null),
  ];

  for (final (text, expected) in strictCases) {
    test('streng: „$text“ → $expected', () {
      expect(recognizer.parse(text, strict: true), expected);
    });
  }

  for (final (text, expected) in cases) {
    test('„$text“ → $expected', () {
      expect(recognizer.parse(text), expected);
    });
  }

  test('Wortgrenze: Teilwörter zählen nicht („Januar“, „nonstop“)', () {
    expect(recognizer.parse('Januar'), isNull);
    expect(recognizer.parse('nonstop'), isNull);
    expect(recognizer.parse('notiz'), isNull);
  });

  test('maxWords ist einstellbar', () {
    const strict = YesNoRecognizer(maxWords: 1);
    expect(strict.parse('Ja'), YesNo.yes);
    expect(strict.parse('Ja bitte'), isNull);
  });
}
