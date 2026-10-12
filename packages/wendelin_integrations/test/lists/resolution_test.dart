import 'package:test/test.dart';
import 'package:wendelin_integrations/src/lists/lists.dart';
import 'package:wendelin_integrations/src/lists/matching.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

final _lists = [
  ListDefinition(
    id: 'e',
    name: 'Einkaufen',
    target: 'e.md',
    aliases: ['shopping', 'Supermarkt'],
  ),
  ListDefinition(id: 'd', name: 'Drogerie', target: 'd.md', aliases: ['dm']),
  ListDefinition(id: 's', name: 'SmartSSH', target: 's.md'),
  ListDefinition(id: 'b', name: 'Baumarkt', target: 'b.md'),
  ListDefinition(
    id: 'a',
    name: 'Aufgaben',
    target: 'a.md',
    aliases: ['To-dos'],
  ),
  ListDefinition(id: 'g', name: 'Groceries', target: 'g.md'),
  ListDefinition(id: 'bu', name: 'Bücher', target: 'bu.md', aliases: ['books']),
  ListDefinition(id: 'u1', name: 'Urlaub Packliste', target: 'u1.md'),
  ListDefinition(id: 'u2', name: 'Urlaub Ideen', target: 'u2.md'),
  ListDefinition(id: 'f', name: 'Filme', target: 'f.md', aliases: ['movies']),
];

void main() {
  final env = ListsEnv(FakeListFilePort(), () => _lists);

  const resolved = <String, String>{
    'Einkaufen': 'e',
    'einkaufen': 'e',
    'EINKAUFEN': 'e',
    'Einkaufsliste': 'e',
    'die Einkaufsliste': 'e',
    'Einkaufslisten': 'e',
    'meine Einkaufsliste': 'e',
    'Shopping list': 'e',
    'shopping': 'e',
    'Supermärkte': 'e',
    'DM': 'd',
    'Drogerieliste': 'd',
    'SmartSSH': 's',
    'smart ssh': 's',
    'Smart-SSH': 's',
    'Liste SmartSSH': 's',
    'Baumärkte': 'b',
    'baumarkt liste': 'b',
    'Aufgabe': 'a',
    'todo': 'a',
    'To Do': 'a',
    'grocery list': 'g',
    'groceries': 'g',
    'Buecher': 'bu',
    'Bücherliste': 'bu',
    'book': 'bu',
    'Packliste': 'u1',
    'urlaub ideen': 'u2',
    'Film': 'f',
    'my movie list': 'f',
  };
  resolved.forEach((query, id) {
    test('„$query“ → $id', () {
      expect(env.resolve(query, write: false).id, id);
    });
  });

  Matcher fails(PortErrorKind kind, List<String> mentions) => throwsA(
    isA<PortException>()
        .having((e) => e.kind, 'kind', kind)
        .having((e) => e.message, 'message', stringContainsInOrder(mentions)),
  );

  test('mehrdeutig: „Urlaub“ nennt beide Kandidaten', () {
    expect(
      () => env.resolve('Urlaub', write: false),
      fails(PortErrorKind.rejected, [
        'Mehrdeutig',
        'Urlaub Packliste',
        'Urlaub Ideen',
      ]),
    );
  });

  test('mehrdeutig: gleiche Stufe bei zwei Listen', () {
    final e2 = ListsEnv(
      FakeListFilePort(),
      () => [
        ListDefinition(id: '1', name: 'Einkaufen Rewe', target: '1'),
        ListDefinition(id: '2', name: 'Einkaufen Aldi', target: '2'),
      ],
    );
    expect(
      () => e2.resolve('Einkaufsliste', write: false),
      fails(PortErrorKind.rejected, ['Rewe', 'Aldi']),
    );
    expect(e2.resolve('einkaufen aldi', write: false).id, '2');
  });

  test('genauer Name schlägt Teiltreffer', () {
    final e2 = ListsEnv(
      FakeListFilePort(),
      () => [
        ListDefinition(id: '1', name: 'Einkaufen', target: '1'),
        ListDefinition(id: '2', name: 'Einkaufen dm', target: '2'),
      ],
    );
    expect(e2.resolve('Einkaufen', write: false).id, '1');
    expect(e2.resolve('Einkaufsliste', write: false).id, '1');
  });

  test('unbekannt: Fehler mit vorhandenen Listen', () {
    expect(
      () => env.resolve('Weihnachten', write: false),
      fails(PortErrorKind.notFound, ['Weihnachten', 'Einkaufen', 'Drogerie']),
    );
    expect(
      () => env.resolve('xy', write: false),
      fails(PortErrorKind.notFound, ['Vorhanden']),
    );
  });

  test('keine Listen eingerichtet', () {
    expect(
      () => ListsEnv(
        FakeListFilePort(),
        () => [],
      ).resolve('Einkaufen', write: false),
      fails(PortErrorKind.notFound, ['keine Listen']),
    );
  });

  group('Bausteine', () {
    test('normalizeText', () {
      expect(normalizeText('  Grüße, Straße!  '), 'grusse strasse');
      expect(normalizeText('Café-Bäckerei'), 'cafe backerei');
    });

    test('stemWord', () {
      expect(stemWord('einkaufsliste'), 'einkauf');
      expect(stemWord('einkaufslisten'), 'einkauf');
      expect(stemWord('einkaufen'), 'einkauf');
      expect(stemWord('groceries'), stemWord('grocery'));
      expect(stemWord('aufgaben'), stemWord('aufgabe'));
      expect(stemWord('movies'), stemWord('movie'));
      expect(stemWord('eis'), 'eis');
    });

    test('matchScore Stufen', () {
      expect(matchScore('Smart SSH', 'smartssh'), 3);
      expect(matchScore('Einkaufsliste', 'Einkaufen'), 2);
      expect(matchScore('Urlaub', 'Urlaub Ideen'), 1);
      expect(matchScore('ab', 'abc'), 0);
      expect(matchScore('', 'x'), 0);
      expect(matchScore('die', 'die'), 3);
      expect(matchScore('Milch', 'Brot'), 0);
    });
  });
}
