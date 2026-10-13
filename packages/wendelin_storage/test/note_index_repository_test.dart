// Notizindex (FTS5): Ranking, Präfixe, Diakritika, Ausschnitte, Pflege.
import 'package:test/test.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'support/storage_fixture.dart';

void main() {
  late WendelinStorage storage;
  late NoteIndexRepository notes;
  final t = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

  setUp(() {
    storage = openTestStorage().storage;
    notes = storage.notes;
  });

  tearDown(() => storage.close());

  Future<void> add(String path, String title, String body) =>
      notes.upsert(path, title: title, body: body, modifiedAt: t);

  Future<List<String>> paths(String q, {int limit = 10}) async => [
    for (final h in await notes.search(q, limit: limit)) h.path,
  ];

  group('Ranking (bm25)', () {
    test('Titel wiegt mehr als Text', () async {
      await add('a.md', 'Notizen', 'Hier steht Garten im Text');
      await add('b.md', 'Garten', 'Beete planen');
      await add('c.md', 'Anderes', 'nichts');
      expect(await paths('Garten'), ['b.md', 'a.md']);
    });

    test('mehr passende Wörter vor einem Wort', () async {
      await add('eins.md', 'Eins', 'Tauchen ist schön');
      await add('beide.md', 'Beide', 'Tauchen auf Malta');
      await add('zwei.md', 'Zwei', 'Malta im Herbst');
      final r = await paths('Tauchen Malta');
      expect(r.first, 'beide.md');
      expect(r, hasLength(3));
    });

    test('häufigeres Vorkommen bei gleicher Länge zuerst', () async {
      await add('selten.md', 'S', 'Kaffee Wasser Wasser Wasser Wasser');
      await add('oft.md', 'O', 'Kaffee Kaffee Kaffee Kaffee Wasser');
      expect((await paths('Kaffee')).first, 'oft.md');
    });

    test('kurze Notiz vor langer bei einem Treffer', () async {
      await add(
        'lang.md',
        'L',
        'Kiwi ${List.filled(200, 'Füllwort').join(' ')}',
      );
      await add('kurz.md', 'K', 'Kiwi und Apfel');
      expect(await paths('Kiwi'), ['kurz.md', 'lang.md']);
    });

    test('gleicher Rang: nach Pfad sortiert (stabil)', () async {
      await add('b.md', 'X', 'gleich');
      await add('a.md', 'X', 'gleich');
      expect(await paths('gleich'), ['a.md', 'b.md']);
    });
  });

  group('Suche', () {
    test('Präfixe, Groß/Klein, Diakritika', () async {
      await add('Übergabe.md', 'Übergabe', 'Café mit Grüßen an Zoë');
      expect(await paths('uberg'), ['Übergabe.md']);
      expect(await paths('CAFE'), ['Übergabe.md']);
      expect(await paths('zoe'), ['Übergabe.md']);
      expect(await paths('Grüße'), ['Übergabe.md']);
    });

    test('Stoppwörter und Einzelzeichen allein finden nichts', () async {
      await add('a.md', 'Die Liste', 'und der die das a b');
      expect(await paths('und der die'), isEmpty);
      expect(await paths('a'), isEmpty);
      expect(await paths(''), isEmpty);
      expect(await notes.search('Liste', limit: 0), isEmpty);
    });

    test('Sonderzeichen werfen nicht', () async {
      await add('a.md', 'A', 'Gemeinsam');
      for (final q in [
        '"',
        '*',
        'NOT',
        'Gemeinsam AND "x',
        'col:umn',
        '(Gemeinsam',
        'NEAR(a b)',
        '-Gemeinsam',
        '^Gemeinsam',
        "'; DROP TABLE note_fts; --",
      ]) {
        await notes.search(q);
      }
      expect(await paths('Gemeinsam'), ['a.md']);
    });

    test('limit', () async {
      for (var i = 0; i < 12; i++) {
        await add('n$i.md', 'N$i', 'Gemeinsam');
      }
      expect(await paths('Gemeinsam', limit: 5), hasLength(5));
      expect(await paths('Gemeinsam'), hasLength(10));
    });

    test('Ausschnitt um den Treffer, einzeilig und kurz', () async {
      final filler = List.filled(80, 'Fülltext').join(' ');
      await add('lang.md', 'Lang', '$filler\nSchatzkarte\n\n$filler');
      final hit = (await notes.search('Schatzkarte')).single;
      expect(hit.snippet, contains('Schatzkarte'));
      expect(hit.snippet, isNot(contains('\n')));
      expect(hit.snippet.length, lessThan(300));
      expect(hit.title, 'Lang');
    });
  });

  group('Pflege', () {
    test('upsert ersetzt Text, Titel und Zeit', () async {
      await add('n.md', 'Alt', 'Apfel');
      final later = t.add(const Duration(minutes: 1));
      await notes.upsert(
        'n.md',
        title: 'Neu',
        body: 'Birne',
        modifiedAt: later,
      );
      expect(await paths('Apfel'), isEmpty);
      expect(await paths('Alt'), isEmpty);
      expect((await notes.search('Birne')).single.title, 'Neu');
      expect(await notes.count(), 1);
      expect((await notes.knownFiles())['n.md'], later.toLocal());
    });

    test('knownFiles mikrosekundengenau', () async {
      await add('x/ä.md', 'ä', '');
      final known = await notes.knownFiles();
      expect(known.keys, ['x/ä.md']);
      expect(known['x/ä.md']!.isAtSameMomentAs(t), isTrue);
      expect(known['x/ä.md']!.microsecondsSinceEpoch, t.microsecondsSinceEpoch);
    });

    test('remove und clear', () async {
      await add('weg.md', 'W', 'Kiwi');
      await add('da.md', 'D', 'Kiwi');
      await notes.remove('weg.md');
      await notes.remove('gab-es-nie.md');
      expect(await paths('Kiwi'), ['da.md']);
      expect((await notes.knownFiles()).keys, ['da.md']);
      await notes.clear();
      expect(await notes.count(), 0);
      expect(await paths('Kiwi'), isEmpty);
    });

    test('Werteobjekt', () {
      const a = NoteSearchHit(path: 'p', title: 't', snippet: 's');
      expect(a, const NoteSearchHit(path: 'p', title: 't', snippet: 's'));
      expect(
        a.hashCode,
        const NoteSearchHit(path: 'p', title: 't', snippet: 's').hashCode,
      );
      expect(
        a,
        isNot(const NoteSearchHit(path: 'q', title: 't', snippet: 's')),
      );
      expect(a.toString(), 'NoteSearchHit(p)');
    });
  });
}
