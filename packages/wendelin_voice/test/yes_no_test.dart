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
    ('Oui', YesNo.yes),
    ("D'accord", YesNo.yes),
    ('Bien sûr', YesNo.yes),
    ('Yes', YesNo.yes),
    ('Go ahead', YesNo.yes),
    ('Klar', YesNo.yes),
    // WP140: eindeutige Zustimmung mit Höflichkeit/Auftrag zählt (de/en/fr).
    ('Ja, bitte', YesNo.yes),
    ('Ja, bitte!', YesNo.yes),
    ('Ja, mach', YesNo.yes),
    ('Ja, mach das', YesNo.yes),
    ('Okay, mach das', null),
    ('OK, mach das', null),
    ('Ja ja', YesNo.yes),
    ('Ja ja ja', YesNo.yes),
    ('Ja gerne bitte', YesNo.yes),
    ('Jawohl', YesNo.yes),
    ('Jo', YesNo.yes),
    ('Jaaa', YesNo.yes),
    ('Äh, ja', YesNo.yes),
    ('Ähm ja bitte', YesNo.yes),
    ('Also ja', YesNo.yes),
    ('Natürlich', YesNo.yes),
    ('Klar, bitte', YesNo.yes),
    ('Yes please', YesNo.yes),
    ('Yes, do it', YesNo.yes),
    ('Absolutely', YesNo.yes),
    ('Oui, vas-y', YesNo.yes),
    ('Oui s’il vous plaît', YesNo.yes),
    ('Oui, tout à fait', YesNo.yes),
    ('Euh oui', YesNo.yes),
    // Verneinung/Einschränkung bleibt nie ein Ja.
    ('Ja, aber nicht', YesNo.no),
    ('Ja nein', null),
    ('Nein ja', null),
    ('Nicht', YesNo.no),
    ('Ja, aber', null),
    ('Ja, nicht jetzt', null),
    ('Ja bitte nicht', null),
    ('Yes but no', YesNo.no),
    ('Oui mais non', YesNo.no),
    ('Ja, mach nicht', null),
    ('Ja, bitte warte', null),
    ('Ja, lösch ihn.', null),
    ('Ja, mach das Schloss auf', null),
    ('Bitte', null),
    ('Mach das', YesNo.yes),
    ('Garage öffnen', null),
    ('Ja bitte ja bitte', YesNo.yes),
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

  // Parakeet macht aus „Nee/Nein/Non“ oft „Yeah.“/„Okay.“/„All right.“:
  // streng zählen nur Zustimmungswörter der eingestellten Sprache.
  group('streng je Sprache', () {
    YesNo? de(String t) => recognizer.parse(t, strict: true, language: 'de');

    for (final t in [
      'Yeah.',
      'Okay.',
      'OK',
      'All right.',
      'Alright',
      'Sure',
      'Right',
      'Yes',
      'Okay, mach das',
      'Yeah, bitte',
      'Ja okay yeah',
    ]) {
      test('de: „$t“ ist streng kein Ja', () {
        expect(de(t), isNot(YesNo.yes));
      });
    }
    for (final t in [
      'Ja',
      'Jawohl',
      'Jo',
      'Genau',
      'Klar',
      'Ja, bitte',
      'Mach das',
      'Klar, bitte',
      'Na klar',
      'In Ordnung',
      'Ja, mach das',
    ]) {
      test('de: „$t“ ist streng ein Ja', () => expect(de(t), YesNo.yes));
    }
    test('de: Nein bleibt Nein, Yeah/Okay normal (nicht streng) Ja', () {
      expect(de('Nein'), YesNo.no);
      expect(recognizer.parse('Yeah.', language: 'de'), YesNo.yes);
      expect(recognizer.parse('Okay.', language: 'de'), YesNo.yes);
    });
    test('en/fr: eigene Zustimmung zählt', () {
      expect(recognizer.parse('Yeah', strict: true, language: 'en'), YesNo.yes);
      expect(recognizer.parse('Okay', strict: true, language: 'en'), YesNo.yes);
      expect(
        recognizer.parse('All right', strict: true, language: 'en'),
        YesNo.yes,
      );
      expect(recognizer.parse('Yeah', strict: true, language: 'fr'), isNull);
      expect(recognizer.parse('Oui', strict: true, language: 'fr'), YesNo.yes);
      expect(recognizer.parse('Oui', strict: true, language: 'en'), isNull);
    });
    test('unbekannte Sprache: Fehlhör-Wörter zählen nicht', () {
      expect(recognizer.parse('Yeah', strict: true), isNull);
      expect(
        recognizer.parse('All right', strict: true, language: 'xx'),
        isNull,
      );
      expect(recognizer.parse('Yes', strict: true, language: 'xx'), YesNo.yes);
    });
  });

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

  group('Antwortverben vor SMS und Anruf (WP85)', () {
    const sms = YesNoRecognizer.smsYesWords;
    const call = YesNoRecognizer.callYesWords;
    YesNo? ask(String t, Set<String> extra) =>
        recognizer.parse(t, strict: true, extraYes: extra);

    test('absenden/anrufen führen aus, ja ebenso, nein/abbrechen nicht', () {
      expect(ask('absenden', sms), YesNo.yes);
      expect(ask('Ja, absenden', sms), YesNo.yes);
      expect(ask('send', sms), YesNo.yes);
      expect(ask('anrufen', call), YesNo.yes);
      expect(ask('Ja', call), YesNo.yes);
      expect(ask('call', call), YesNo.yes);
      expect(ask('nein', sms), YesNo.no);
      expect(ask('abbrechen', call), YesNo.no);
    });

    test('Verneinung und Unklares führen nichts aus', () {
      expect(ask('nicht absenden', sms), isNull);
      expect(ask('nicht anrufen', call), isNull);
      expect(ask('vielleicht', sms), isNull);
      expect(ask('mal sehen', call), isNull);
      expect(ask('ja absenden aber später bitte noch mal', sms), isNull);
    });

    test('das Verb der anderen Frage bestätigt nicht', () {
      expect(ask('anrufen', sms), isNull);
      expect(ask('absenden', call), isNull);
      expect(recognizer.parse('absenden'), isNull);
    });
  });
}
