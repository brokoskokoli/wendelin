import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

void main() {
  group('normalize', () {
    final cases = <(String, String)>[
      ('Claude, trag das ein!', 'claude trag das ein'),
      ('  „Claude“ – los…  ', 'claude los'),
      ('ÄÖÜ äöü ß', 'aou aou ss'),
      ('Réécris ça, s’il te plaît', 'reecris ca s il te plait'),
      ('Œuvre Æsir', 'oeuvre aesir'),
      ('été', 'ete'), // decomposed accents
      ('Termin 14:30', 'termin 14 30'),
      ('???', ''),
      ('', ''),
      ('Emoji 😀 test', 'emoji test'),
    ];
    for (final (input, expected) in cases) {
      test('„$input“ → „$expected“', () {
        expect(RoutingText.normalize(input), expected);
      });
    }
  });

  test('phrases match whole words only', () {
    final t = RoutingText('Hallo Claude, Claudia!');
    expect(t.findPhrase('claude'), const TriggerSpan(6, 12));
    expect(t.findPhrase('claud'), isNull);
    expect(t.findPhrase('CLAUDIA'), const TriggerSpan(13, 20));
    expect(t.findPhrase(''), isNull);
    expect(t.findPhrase('claude', from: 7), isNull);
    expect(RoutingText('aa a').findPhrase('a'), const TriggerSpan(3, 4));
    expect(t.startsWithPhrase('hallo'), const TriggerSpan(0, 5));
    expect(t.startsWithPhrase('hall'), isNull);
    expect(t.startsWithPhrase('claude'), isNull);
    expect(t.startsWithPhrase('!!'), isNull);
  });

  group('without', () {
    final cases = <(String, String, String?)>[
      ('Claude, trag den Termin ein', 'claude', 'trag den Termin ein'),
      ('Claude:trag ein', 'claude', 'trag ein'),
      ('Bitte privat notieren.', 'privat', 'Bitte notieren.'),
      ('Notiere das privat.', 'privat', 'Notiere das'),
      ('Notiere das privat , ok', 'privat', 'Notiere das ok'),
      ('Größe ändern, Claude', 'claude', 'Größe ändern,'),
      ('Claude.', 'claude', null),
      ('Claude – ', 'claude', null),
      ('Ärger, schreib', 'arger', 'schreib'),
    ];
    for (final (text, phrase, expected) in cases) {
      test('„$text“ minus „$phrase“ → ${expected ?? 'null'}', () {
        final t = RoutingText(text);
        expect(t.without([t.findPhrase(phrase)!]), expected);
      });
    }

    test('several and overlapping spans', () {
      final t = RoutingText('Claude privat trag ein');
      final a = t.findPhrase('claude')!;
      final b = t.findPhrase('privat')!;
      expect(t.without([b, a]), 'trag ein');
      expect(t.without([a, a]), 'privat trag ein');
      expect(t.without(const []), 'Claude privat trag ein');
      expect(t.without([const TriggerSpan(6, 7)]), 'Claude privat trag ein');
      expect(t.without([a, const TriggerSpan(3, 13)]), 'trag ein');
    });
  });

  test('value semantics', () {
    expect(RoutingText('a'), RoutingText('a'));
    expect(RoutingText('a').hashCode, RoutingText('a').hashCode);
    expect(RoutingText('a'), isNot(RoutingText('A')));
    expect(RoutingText('A!').toString(), 'RoutingText("a")');
    expect(const TriggerSpan(1, 2).hashCode, const TriggerSpan(1, 2).hashCode);
    expect(const TriggerSpan(1, 2).toString(), 'TriggerSpan(1, 2)');
  });
}
