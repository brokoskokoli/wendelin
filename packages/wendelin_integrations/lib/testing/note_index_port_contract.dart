import 'dart:async';

import 'package:test/test.dart';

import '../src/obsidian/ports.dart';

/// Creates an **empty** [NoteIndexPort] under test.
typedef NoteIndexFactory = FutureOr<NoteIndexPort> Function();

/// Names of the checks in [noteIndexPortContractChecks].
abstract final class NoteIndexChecks {
  /// Body and title words are found, as prefixes.
  static const find = 'findet Wörter in Titel und Text, auch als Präfix';

  /// Case and diacritics are ignored.
  static const fold = 'Groß/Klein und Umlaute/Akzente egal';

  /// Title matches rank above body matches.
  static const titleFirst = 'Treffer im Titel vor Treffer im Text';

  /// More matching words rank higher.
  static const moreTerms = 'mehr passende Wörter zuerst';

  /// upsert replaces the old entry.
  static const replace = 'upsert ersetzt den alten Stand (ein Treffer je Pfad)';

  /// remove deletes, unknown paths are fine.
  static const remove = 'remove entfernt; unbekannter Pfad ist kein Fehler';

  /// knownFiles reports the exact modification times.
  static const known = 'knownFiles liefert Pfade mit exaktem modifiedAt';

  /// limit, blank queries and special characters.
  static const limits =
      'limit wird eingehalten; leere Anfrage und Sonderzeichen werfen nicht';

  /// Snippet around the match.
  static const snippet = 'Ausschnitt enthält das Suchwort und ist kurz';
}

/// Reusable contract suite for every [NoteIndexPort] (`FakeNoteIndex`,
/// the app's adapter on `NoteIndexRepository`); registers one test per
/// entry of [noteIndexPortContractChecks].
void noteIndexPortContract(
  NoteIndexFactory create, {
  String name = 'NoteIndexPort',
}) {
  group('$name erfüllt den NoteIndexPort-Vertrag', () {
    noteIndexPortContractChecks(create).forEach(test);
  });
}

/// The checks of [noteIndexPortContract] by name ([NoteIndexChecks]).
Map<String, Future<void> Function()> noteIndexPortContractChecks(
  NoteIndexFactory create,
) {
  final t = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

  Future<NoteIndexPort> seeded(Map<String, (String, String)> notes) async {
    final index = await create();
    var k = 0;
    for (final MapEntry(key: path, value: (title, body)) in notes.entries) {
      await index.upsert(
        path,
        title: title,
        body: body,
        modifiedAt: t.add(Duration(minutes: k++)),
      );
    }
    return index;
  }

  Future<List<String>> paths(
    NoteIndexPort i,
    String q, {
    int limit = 10,
  }) async => [for (final h in await i.search(q, limit: limit)) h.path];

  return {
    NoteIndexChecks.find: () async {
      final i = await seeded({
        'Reisen/Malta.md': (
          'Malta',
          'Tauchen im Oktober, Unterkunft in Sliema',
        ),
        'Projekte/Wendelin.md': ('Wendelin', 'Sprachassistent mit Obsidian'),
      });
      expect(await paths(i, 'Sliema'), ['Reisen/Malta.md']);
      expect(await paths(i, 'Wendelin'), ['Projekte/Wendelin.md']);
      expect(await paths(i, 'Sprachass'), ['Projekte/Wendelin.md']);
      expect(await paths(i, 'Unbekanntwort'), isEmpty);
      final hit = (await i.search('Sliema')).single;
      expect(hit.title, 'Malta');
    },
    NoteIndexChecks.fold: () async {
      final i = await seeded({
        'Übergabe.md': ('Übergabe', 'Café mit Grüßen an Zoë'),
      });
      expect(await paths(i, 'ubergabe'), ['Übergabe.md']);
      expect(await paths(i, 'CAFE'), ['Übergabe.md']);
      expect(await paths(i, 'zoe'), ['Übergabe.md']);
    },
    NoteIndexChecks.titleFirst: () async {
      final i = await seeded({
        'a.md': ('Notizen', 'Hier steht Garten irgendwo im langen Text drin'),
        'b.md': ('Garten', 'Beete planen'),
      });
      expect(await paths(i, 'Garten'), ['b.md', 'a.md']);
    },
    NoteIndexChecks.moreTerms: () async {
      final i = await seeded({
        'eins.md': ('Eins', 'Tauchen ist schön'),
        'beide.md': ('Beide', 'Tauchen auf Malta'),
        'zwei.md': ('Zwei', 'Malta im Herbst'),
      });
      expect((await paths(i, 'Tauchen Malta')).first, 'beide.md');
      expect(await paths(i, 'Tauchen Malta'), hasLength(3));
    },
    NoteIndexChecks.replace: () async {
      final i = await seeded({'n.md': ('N', 'alter Inhalt Apfel')});
      await i.upsert(
        'n.md',
        title: 'N',
        body: 'neuer Inhalt Birne',
        modifiedAt: t,
      );
      expect(await paths(i, 'Apfel'), isEmpty);
      expect(await paths(i, 'Birne'), ['n.md']);
      expect(await paths(i, 'Inhalt'), ['n.md']);
    },
    NoteIndexChecks.remove: () async {
      final i = await seeded({
        'weg.md': ('Weg', 'Kiwi'),
        'da.md': ('Da', 'Kiwi'),
      });
      await i.remove('weg.md');
      await i.remove('gab-es-nie.md');
      expect(await paths(i, 'Kiwi'), ['da.md']);
      expect((await i.knownFiles()).keys, ['da.md']);
    },
    NoteIndexChecks.known: () async {
      final i = await create();
      expect(await i.knownFiles(), isEmpty);
      await i.upsert('x/ä.md', title: 'ä', body: '', modifiedAt: t);
      final local = DateTime(2026, 3, 29, 2, 30);
      await i.upsert('y.md', title: 'y', body: 'b', modifiedAt: local);
      final known = await i.knownFiles();
      expect(known.keys.toSet(), {'x/ä.md', 'y.md'});
      expect(known['x/ä.md']!.isAtSameMomentAs(t), isTrue);
      expect(known['y.md']!.isAtSameMomentAs(local), isTrue);
    },
    NoteIndexChecks.limits: () async {
      final i = await seeded({
        for (var k = 0; k < 12; k++) 'n$k.md': ('Notiz $k', 'Gemeinsam $k'),
      });
      expect(await paths(i, 'Gemeinsam', limit: 5), hasLength(5));
      expect(await paths(i, 'Gemeinsam'), hasLength(10));
      for (final q in [
        '',
        '   ',
        '"',
        '*',
        'a',
        'NOT',
        'Gemeinsam AND "x',
        'col:umn',
        '(Gemeinsam',
        'NEAR(a b)',
        '-Gemeinsam',
        '^Gemeinsam',
      ]) {
        await i.search(q);
      }
      expect(await paths(i, '"Gemeinsam"', limit: 3), hasLength(3));
    },
    NoteIndexChecks.snippet: () async {
      final filler = List.filled(80, 'Fülltext').join(' ');
      final i = await seeded({
        'lang.md': ('Lang', '$filler Schatzkarte $filler'),
      });
      final hit = (await i.search('Schatzkarte')).single;
      expect(hit.snippet.toLowerCase(), contains('schatzkarte'));
      expect(hit.snippet.length, lessThan(300));
    },
  };
}
