import 'package:test/test.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

HintTerm room(String t) => HintTerm(t, HintTermKind.room);

void main() {
  test('Namen kommen durch, Leerraum wird bereinigt', () {
    expect(
      sanitizeHintTerms([
        room('  Wohnzimmer   Licht '),
        const HintTerm('Mia Berger', HintTermKind.contact),
        const HintTerm('Wendelin-Test', HintTermKind.list),
      ]),
      ['Wendelin-Test', 'Wohnzimmer Licht', 'Mia Berger'],
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
    final many = [for (var i = 0; i < 400; i++) room('Raum $i a')];
    expect(const HintTermLimits().maxTerms, 128);
    expect(sanitizeHintTerms(many).length, 128);
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

  test('Doppelte ohne Rücksicht auf Groß/Klein; der höhere Rang bleibt', () {
    expect(
      sanitizeHintTerms([
        room('Küche'),
        const HintTerm('küche', HintTermKind.contact),
        const HintTerm('Agent Eins', HintTermKind.agent),
      ]),
      ['Agent Eins', 'Küche'],
    );
  });

  test('Reihenfolge: Agent, Liste, Raum, Entität, Synonym, Kontakt', () {
    expect(
      sanitizeHintTerms(const [
        HintTerm('Anna', HintTermKind.contact),
        HintTerm('Lampe', HintTermKind.synonym),
        HintTerm('Deckenlicht', HintTermKind.entity),
        HintTerm('Küche', HintTermKind.room),
        HintTerm('Einkaufen', HintTermKind.list),
        HintTerm('Wendelin', HintTermKind.agent),
      ]),
      ['Wendelin', 'Einkaufen', 'Küche', 'Deckenlicht', 'Lampe', 'Anna'],
    );
  });

  test('Kürzen an der Grenze: Kontakte fallen zuerst, dann Synonyme', () {
    final terms = [
      for (var i = 0; i < 5; i++)
        HintTerm('Kontakt${'a' * i}', HintTermKind.contact),
      const HintTerm('Lampe', HintTermKind.synonym),
      const HintTerm('Deckenlicht', HintTermKind.entity),
      const HintTerm('Einkaufen', HintTermKind.list),
    ];
    List<String> cut(int n) =>
        sanitizeHintTerms(terms, limits: HintTermLimits(maxTerms: n));
    expect(cut(3), ['Einkaufen', 'Deckenlicht', 'Lampe']);
    expect(cut(4), ['Einkaufen', 'Deckenlicht', 'Lampe', 'Kontakt']);
    expect(cut(2), ['Einkaufen', 'Deckenlicht']);
  });

  test('Dedupe: der Entitätsname schlägt das gleiche Synonym', () {
    final out = sanitizeHintTermsKinded(const [
      HintTerm('lampe', HintTermKind.synonym),
      HintTerm('Lampe', HintTermKind.entity),
    ]);
    expect(out.single.text, 'Lampe');
    expect(out.single.kind, HintTermKind.entity);
  });

  test('Zählung je Art ohne Namen', () {
    final counts = countHintTerms(const [
      HintTerm('A', HintTermKind.list),
      HintTerm('B', HintTermKind.list),
      HintTerm('C', HintTermKind.contact),
    ]);
    expect(counts[HintTermKind.list], 2);
    expect(counts[HintTermKind.contact], 1);
    expect(counts[HintTermKind.synonym], 0);
  });

  test('Quellen: eine fehlerhafte Quelle wird übersprungen', () async {
    final out = await collectHintTerms([
      FakeHintTermSource([room('Küche')]),
      FakeHintTermSource(const [], failure: StateError('weg')),
      FakeHintTermSource([const HintTerm('Anna', HintTermKind.contact)]),
    ]);
    expect(out, ['Küche', 'Anna']);
  });

  test('Begriff schreibt keinen Inhalt in toString', () {
    expect(room('Geheim').toString(), isNot(contains('Geheim')));
  });
}
