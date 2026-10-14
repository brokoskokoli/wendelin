import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const restDe = 'Den Rest siehst du auf dem Bildschirm.';
const restFr = 'La suite est à l’écran.';
const restEn = 'The rest is on the screen.';

List<String> streamed(String text, {String? language, int step = 1}) {
  final a = SpokenAnswer(language: language);
  final out = <String>[];
  for (var i = 0; i < text.length; i += step) {
    out.addAll(
      a.add(text.substring(i, i + step > text.length ? text.length : i + step)),
    );
  }
  return out..addAll(a.finish());
}

void main() {
  final long = List.filled(30, 'Wort').join(' ');
  final veryLong = List.filled(100, 'Wort').join(' ');

  // language, input, expected spoken sentences
  final table = <(String, String, String, List<String>)>[
    // ---- de
    (
      'de: zwei Sätze bleiben',
      'de',
      'Es ist 10.30 Uhr. Du hast heute drei Termine.',
      ['Es ist 10.30 Uhr.', 'Du hast heute drei Termine.'],
    ),
    (
      'de: Fett und Link-Text, URL weg',
      'de',
      '**Wichtig:** Der Termin steht [hier](https://example.com/x) drin.',
      ['Wichtig. Der Termin steht hier drin.'],
    ),
    (
      'de: nackte URL entfernt, Satzende bleibt',
      'de',
      'Mehr steht unter https://example.com/a?b=1. Sonst nichts.',
      ['Mehr steht unter.', 'Sonst nichts.'],
    ),
    (
      'de: lange Liste zusammengefasst',
      'de',
      'Deine Einkaufsliste:\n- Milch\n- Brot\n- Eier\n- Butter\n- Käse\n'
          '- Äpfel\n- Mehl',
      ['Deine Einkaufsliste.', 'Milch, Brot, Eier und 4 weitere.'],
    ),
    (
      'de: kurze nummerierte Liste ausgeschrieben',
      'de',
      'Offen sind:\n1. Steuer\n2. Arzt.\n3. Auto',
      ['Offen sind.', 'Steuer, Arzt und Auto.'],
    ),
    (
      'de: Checkboxen und Unterpunkte',
      'de',
      '- [ ] Milch\n  - fettarm\n- [x] Brot\n\nDas war alles.',
      ['Milch und Brot.', 'Das war alles.'],
    ),
    (
      'de: höchstens drei Sätze, dann Hinweis',
      'de',
      'Eins. Zwei. Drei. Vier. Fünf.',
      ['Eins.', 'Zwei.', 'Drei.', restDe],
    ),
    (
      'de: Codeblock nur auf dem Bildschirm',
      'de',
      'So geht es:\n```dart\nprint(1);\n```\nFertig.',
      ['So geht es.', 'Fertig.', restDe],
    ),
    (
      'de: Tabelle nur auf dem Bildschirm',
      'de',
      'Die Werte:\n| a | b |\n|---|---|\n| 1 | 2 |\nEnde.',
      ['Die Werte.', 'Ende.', restDe],
    ),
    (
      'de: Überschrift, Zitat, Trennlinie, Inline-Code',
      'de',
      '## Ergebnis\n> Alles gut.\n---\nNutze `ls` dafür.',
      ['Ergebnis', 'Alles gut.', 'Nutze ls dafür.'],
    ),
    (
      'de: 400 Zeichen: zweiter langer Satz entfällt',
      'de',
      '$long. $long. $long.',
      ['$long.', '$long.', restDe],
    ),
    (
      'de: erster Satz allein zu lang wird am Wort gekürzt',
      'de',
      '$veryLong.',
      ['${veryLong.substring(0, 399)}…', restDe],
    ),
    ('de: nur Code ergibt nur den Hinweis', 'de', '```\nx\n```', [restDe]),
    // ---- fr
    (
      'fr: Liste mit „et N autres“',
      'fr',
      'Voici ta liste :\n- lait\n- pain\n- œufs\n- beurre\n- fromage',
      ['Voici ta liste.', 'lait, pain, œufs et 2 autres.'],
    ),
    ('fr: kurze Liste mit „et“', 'fr', '* lait\n* pain', ['lait et pain.']),
    (
      'fr: Hinweis auf Französisch',
      'fr',
      'Un. Deux. Trois. Quatre.',
      ['Un.', 'Deux.', 'Trois.', restFr],
    ),
    (
      'fr: eine weitere Position',
      'fr',
      '- a\n- b\n- c\n- d',
      ['a, b, c et 1 autre.'],
    ),
    // ---- en
    (
      'en: list with „and N more“',
      'en',
      'You have:\n+ apples\n+ pears\n+ plums\n+ figs\n+ kiwis',
      ['You have.', 'apples, pears, plums and 2 more.'],
    ),
    (
      'en: URL in angle brackets removed',
      'en',
      'See <https://example.com> for details. Done.',
      ['See for details.', 'Done.'],
    ),
    (
      'en: hint in English',
      'en-GB',
      'One. Two. Three. Four.',
      ['One.', 'Two.', 'Three.', restEn],
    ),
    (
      'unbekannte Sprache fällt auf Deutsch zurück',
      'xx',
      'Eins. Zwei. Drei. Vier.',
      ['Eins.', 'Zwei.', 'Drei.', restDe],
    ),
  ];

  group('Kürzungstabelle', () {
    for (final (name, lang, input, expected) in table) {
      test(name, () {
        expect(SpokenAnswer.shorten(input, language: lang), expected);
      });
      test('$name (gestreamt, zeichenweise)', () {
        expect(streamed(input, language: lang), expected);
      });
    }
  });

  group('Streaming', () {
    test('erster Satz kommt, bevor die Antwort fertig ist', () {
      final a = SpokenAnswer();
      expect(a.add('Hallo Stefan. Heu'), isEmpty);
      expect(a.add('te ist Dienstag'), ['Hallo Stefan.']);
      expect(a.finish(), ['Heute ist Dienstag']);
      expect(a.finish(), isEmpty);
      expect(a.add('Noch was.'), isEmpty);
    });

    test('Zeile mit Fett am Anfang wird gestreamt, nicht gepuffert', () {
      final a = SpokenAnswer();
      expect(a.add('**Achtung:** Das ist wichtig. Und '), [
        'Achtung. Das ist wichtig.',
      ]);
    });

    test('Liste wird erst nach ihrem Ende gesprochen', () {
      final a = SpokenAnswer();
      expect(a.add('- Milch\n- Brot\n'), isEmpty);
      expect(a.add('Sonst'), ['Milch und Brot.']);
      expect(a.add(' nichts.\n'), ['Sonst nichts.']);
    });

    test('Absatz ohne Satzzeichen endet an der Zeile', () {
      expect(streamed('Titel\nText.', step: 3), ['Titel', 'Text.']);
    });

    test('endSegment gibt den Rest vor einem Tool-Aufruf frei', () {
      final a = SpokenAnswer();
      expect(a.add('Ich schaue nach'), isEmpty);
      expect(a.endSegment(), ['Ich schaue nach']);
      expect(a.add('Morgen regnet es.'), isEmpty);
      expect(a.finish(), ['Morgen regnet es.']);
    });

    test('endSegment beendet auch eine offene Liste', () {
      final a = SpokenAnswer();
      a.add('- a\n- b');
      expect(a.endSegment(), ['a und b.']);
    });

    test('nach finish nimmt endSegment nichts mehr an', () {
      final a = SpokenAnswer()..finish();
      expect(a.endSegment(), isEmpty);
    });
  });

  group('reset (AgentTextReset)', () {
    test('verwirft den gepufferten Teil des Abschnitts', () {
      final a = SpokenAnswer();
      expect(a.add('Falsch angefangen. Und noch'), ['Falsch angefangen.']);
      a.reset(unspoken: ['Falsch angefangen.']);
      expect(a.add('Richtig.'), isEmpty);
      expect(a.finish(), ['Richtig.']);
    });

    test('nicht gesprochene Sätze zählen nicht zum Limit', () {
      final a = SpokenAnswer(config: const SpeechShortening(maxSentences: 2));
      final first = a.add('Eins. Zwei. Drei. Vier ');
      expect(first, ['Eins.', 'Zwei.']);
      expect(a.truncated, isTrue);
      a.reset(unspoken: ['Zwei.']);
      expect(a.truncated, isFalse);
      expect(a.add('Neu. Mehr '), ['Neu.']);
      expect(a.finish(), [restDe]);
    });

    test('gesprochene Sätze bleiben im Limit', () {
      final a = SpokenAnswer(config: const SpeechShortening(maxSentences: 1));
      expect(a.add('Eins. Zwei '), ['Eins.']);
      a.reset();
      expect(a.add('Drei. Vier '), isEmpty);
      expect(a.truncated, isTrue);
    });

    test('verworfener Codeblock löst keinen Hinweis mehr aus', () {
      final a = SpokenAnswer();
      a.add('```\ncode\n```\n');
      expect(a.omitted, isTrue);
      a.reset();
      expect(a.omitted, isFalse);
      expect(a.add('Gut.\n'), ['Gut.']);
      expect(a.finish(), isEmpty);
    });

    test('Abschnitt vor dem Tool bleibt beim Reset gültig', () {
      final a = SpokenAnswer(config: const SpeechShortening(maxSentences: 1));
      expect(a.add('Eins. Zwei '), ['Eins.']);
      a.endSegment();
      a.reset();
      expect(a.truncated, isTrue);
    });

    test('reset hebt finish auf (neuer Anlauf nach Abbruch)', () {
      final a = SpokenAnswer()..finish();
      a.reset();
      expect(a.add('Neu.\n'), ['Neu.']);
    });
  });

  test('ohne announceRest kein Hinweis', () {
    expect(
      SpokenAnswer.shorten(
        'Eins. Zwei. Drei. Vier.',
        config: const SpeechShortening(announceRest: false),
      ),
      ['Eins.', 'Zwei.', 'Drei.'],
    );
  });

  group('cleanForSpeech', () {
    final cases = <(String, String)>[
      ('*kursiv* und _auch_', 'kursiv und auch'),
      ('snake_case_name bleibt', 'snake_case_name bleibt'),
      ('~~alt~~ neu', 'alt neu'),
      ('![Bild](a.png) Text', 'Text'),
      ('www.example.com ist gut.', 'ist gut.'),
      ('Siehe (https://x.de).', 'Siehe.'),
      ('[](https://x.de)', ''),
      ('---', ''),
      ('Ça va ?', 'Ça va?'),
    ];
    for (final (input, expected) in cases) {
      test('"$input"', () => expect(cleanForSpeech(input), expected));
    }
  });

  group('Review WP15', () {
    test('Überschriften zählen nicht zum Satzlimit', () {
      expect(SpokenAnswer.shorten('# Titel\nEins. Zwei. Drei.'), [
        'Titel',
        'Eins.',
        'Zwei.',
        'Drei.',
      ]);
    });

    test('Text vor einem Tool-Aufruf zählt nicht zum Satzlimit', () {
      final a = SpokenAnswer();
      expect([
        ...a.add('Ich schaue nach. Einen Moment. Gleich da.'),
        ...a.endSegment(),
      ], hasLength(3));
      expect(
        [...a.add('Eins. Zwei. Drei.'), ...a.finish()],
        ['Eins.', 'Zwei.', 'Drei.'],
      );
    });

    test('maxChars: genau an der Grenze passt, ein Zeichen mehr nicht', () {
      // 'Eins zwei drei vier.' = 20, 'Fünf.' = 5 Zeichen.
      const text = 'Eins zwei drei vier. Fünf.';
      expect(
        SpokenAnswer.shorten(
          text,
          config: const SpeechShortening(maxChars: 25),
        ),
        ['Eins zwei drei vier.', 'Fünf.'],
      );
      expect(
        SpokenAnswer.shorten(
          text,
          config: const SpeechShortening(maxChars: 24),
        ),
        ['Eins zwei drei vier.', restDe],
      );
      expect(
        SpokenAnswer.shorten(
          text,
          config: const SpeechShortening(maxChars: 20),
        ),
        ['Eins zwei drei vier.', restDe],
      );
      expect(
        SpokenAnswer.shorten(
          text,
          config: const SpeechShortening(maxChars: 19),
        ),
        ['Eins zwei drei…', restDe],
      );
    });

    test('Emojis werden entfernt', () {
      expect(SpokenAnswer.shorten('Super 🎉👍🏽! Gern geschehen 😊.'), [
        'Super!',
        'Gern geschehen.',
      ]);
      expect(SpokenAnswer.shorten('🇩🇪 👨‍👩‍👧 ✅'), isEmpty);
    });

    test(
      'Satz nur aus einem Link: weggelassen, Hinweis auf den Bildschirm',
      () {
        expect(SpokenAnswer.shorten('Quelle:\nhttps://example.com/a\nDanke.'), [
          'Quelle.',
          'Danke.',
          restDe,
        ]);
      },
    );

    test('Reset: bereits gesprochene Sätze werden beim erneuten Senden übersprungen', () {
      final a = SpokenAnswer();
      expect(a.add('Eins hier. Zwei hier. Drei hier'), [
        'Eins hier.',
        'Zwei hier.',
      ]);
      a.reset(unspoken: ['Zwei hier.']);
      expect(a.add('Eins hier. Zwei hier. Drei hier. Vier'), ['Zwei hier.']);
      // Limit 3: Eins (spoken once), Zwei, Drei – Vier is cut.
      expect(a.add(' hier. Fünf hier'), ['Drei hier.']);
      expect(a.truncated, isTrue);
    });

    test('Reset: abweichender neuer Text beendet das Überspringen', () {
      final a = SpokenAnswer();
      expect(a.add('Eins hier. Zwei hier'), ['Eins hier.']);
      a.reset();
      expect(a.add('Anders. Eins hier. Noch mehr'), ['Anders.', 'Eins hier.']);
    });
  });

  test('VoiceTexts: Fehlertexte je Sprache', () {
    expect(
      VoiceTexts.de.failure(AgentErrorKind.provider, 'Kaputt.'),
      'Kaputt.',
    );
    expect(
      VoiceTexts.de.failure(AgentErrorKind.provider, ' '),
      VoiceTexts.de.failed,
    );
    // The reason of a provider failure is translated by the agent.
    expect(
      VoiceTexts.fr.failure(AgentErrorKind.provider, 'Claude est injoignable.'),
      'Claude est injoignable.',
    );
    expect(
      VoiceTexts.en.failure(AgentErrorKind.provider, ' '),
      VoiceTexts.en.failed,
    );
    expect(
      VoiceTexts.fr.failure(AgentErrorKind.timeout, 'x'),
      VoiceTexts.fr.tooSlow,
    );
    expect(
      VoiceTexts.en.failure(AgentErrorKind.budgetBlocked, 'x'),
      VoiceTexts.en.noBudget,
    );
    expect(
      VoiceTexts.en.failure(AgentErrorKind.tokenBudget, 'x'),
      VoiceTexts.en.noBudget,
    );
    expect(
      VoiceTexts.fr.failure(AgentErrorKind.internal, 'x'),
      VoiceTexts.fr.failed,
    );
  });

  test('VoiceTexts nach Sprache', () {
    expect(VoiceTexts.of('de-AT'), same(VoiceTexts.de));
    expect(VoiceTexts.of('fr_CH'), same(VoiceTexts.fr));
    expect(VoiceTexts.of('EN'), same(VoiceTexts.en));
    expect(VoiceTexts.of(null), same(VoiceTexts.de));
    expect(VoiceTexts.en.nothingUnderstood, isNotEmpty);
    expect(VoiceTexts.fr.more(3), 'et 3 autres');
  });
}
