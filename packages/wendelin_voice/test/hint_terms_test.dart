import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

HintTerm room(String t) => HintTerm(t, HintTermKind.room);

void main() {
  test('Namen kommen durch, Leerraum wird bereinigt', () {
    expect(
      sanitizeHintTerms([
        room('  Wohnzimmer   Licht '),
        const HintTerm('Stefan Richter', HintTermKind.contact),
        const HintTerm('Wendelin-Test', HintTermKind.list),
      ]),
      ['Stefan Richter', 'Wendelin-Test', 'Wohnzimmer Licht'],
    );
  });

  test('Inhalte kommen nicht durch: Sätze, lange Texte, Satzzeichen', () {
    final content = [
      room('Ruf morgen um acht Uhr Frau Meier wegen der Rechnung an'),
      room('Milch, Eier und Brot kaufen'),
      room('Passwort: hunter2'),
      room('Das Konto ist 12345678.'),
      room('Zeile 1\nZeile 2'),
      room('https://example.org/x'),
      room('a' * 41),
      room('12345'),
      room(''),
    ];
    expect(sanitizeHintTerms(content), isEmpty);
  });

  test('Komma und Schrägstrich im kurzen Text: kein Name', () {
    expect(sanitizeHintTerms([room('Müller, Hans')]), isEmpty);
    expect(sanitizeHintTerms([room('Ein/Aus')]), isEmpty);
    expect(sanitizeHintTerms([room('Hans Müller')]), ['Hans Müller']);
  });

  test('Begrenzung: Anzahl, Länge, Wörter einstellbar', () {
    final many = [for (var i = 0; i < 100; i++) room('Raum $i a')];
    expect(sanitizeHintTerms(many).length, 64);
    expect(
      sanitizeHintTerms([
        room('Eins'),
        room('Zwei'),
        room('Drei'),
      ], limits: const HintTermLimits(maxTerms: 2)),
      ['Eins', 'Zwei'],
    );
    expect(
      sanitizeHintTerms([
        room('Ab'),
        room('Abcdefgh'),
      ], limits: const HintTermLimits(maxLength: 5)),
      ['Ab'],
    );
    expect(
      sanitizeHintTerms([
        room('Ein Zwei'),
        room('Ein Zwei Drei'),
      ], limits: const HintTermLimits(maxWords: 2)),
      ['Ein Zwei'],
    );
  });

  test('Doppelte ohne Rücksicht auf Groß/Klein; Kontakte zuerst', () {
    expect(
      sanitizeHintTerms([
        room('Küche'),
        const HintTerm('küche', HintTermKind.contact),
        const HintTerm('Agent Eins', HintTermKind.agent),
      ]),
      ['küche', 'Agent Eins'],
    );
  });

  test('beim Kürzen bleiben die Kontakte, nicht die Entitäten', () {
    final terms = [
      for (var i = 0; i < 5; i++) HintTerm('Entität $i', HintTermKind.entity),
      const HintTerm('Anna', HintTermKind.contact),
    ];
    expect(
      sanitizeHintTerms(terms, limits: const HintTermLimits(maxTerms: 2)),
      ['Anna', 'Entität 0'],
    );
  });

  test('Quellen: eine fehlerhafte Quelle wird übersprungen', () async {
    final out = await collectHintTerms([
      FakeHintTermSource([room('Küche')]),
      FakeHintTermSource(const [], failure: StateError('weg')),
      FakeHintTermSource([const HintTerm('Anna', HintTermKind.contact)]),
    ]);
    expect(out, ['Anna', 'Küche']);
  });

  test('Begriff schreibt keinen Inhalt in toString', () {
    expect(room('Geheim').toString(), isNot(contains('Geheim')));
  });
}
