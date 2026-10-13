import 'package:test/test.dart';
import 'package:wendelin_integrations/src/common/matching.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

/// Env on a fake vault with [files] (index synced on first use).
ObsidianEnv _env(Iterable<String> files, {String locale = 'de'}) {
  final vault = FakeVaultPort(files: {for (final f in files) f: 'x'});
  return ObsidianIntegration(
    vault,
    FakeNoteIndex(),
    settings: () => ObsidianSettings(vaultName: 'V', locale: locale),
  ).env;
}

final _now = DateTime.utc(2026, 10, 13, 12);

Future<NoteResolution> _resolve(
  ObsidianEnv env,
  String query, {
  bool write = false,
}) => env.resolveNoteMatch(query, write: write, now: _now);

Future<PortException> _fails(
  ObsidianEnv env,
  String query, {
  bool write = false,
}) async {
  try {
    final r = await _resolve(env, query, write: write);
    fail('erwartet Fehler, war $r');
  } on PortException catch (e) {
    return e;
  }
}

void main() {
  group('Trefferart und Rangfolge', () {
    const vault = [
      'Wendelin-Test.md',
      'Projekte/Wendelin.md',
      'Reisen/Malta 2026.md',
      'Ideen/Einkaufsliste.md',
      'Archiv/Wendelin Test.md',
      'Archiv/Mein_Urlaub.md',
    ];
    for (final (query, path, kind) in [
      // Exakter Pfad schlägt alles andere.
      ('Wendelin-Test', 'Wendelin-Test.md', NoteMatchKind.exact),
      ('Archiv/Wendelin Test', 'Archiv/Wendelin Test.md', NoteMatchKind.exact),
      // Exakter Titel (ohne Groß/klein) vor gefaltetem.
      ('wendelin test', 'Archiv/Wendelin Test.md', NoteMatchKind.exact),
      ('projekte/wendelin', 'Projekte/Wendelin.md', NoteMatchKind.exact),
      // Gefaltet: Leerzeichen, Bindestrich, Unterstrich, Umlaute.
      ('Wendelin_Test', 'Wendelin-Test.md', NoteMatchKind.folded),
      ('WendelinTest', 'Wendelin-Test.md', NoteMatchKind.folded),
      ('Mein Urlaub', 'Archiv/Mein_Urlaub.md', NoteMatchKind.folded),
      ('Einkaufs-Liste', 'Ideen/Einkaufsliste.md', NoteMatchKind.folded),
      // Unscharf: Wortstämme, ganze Wörter.
      ('Malta', 'Reisen/Malta 2026.md', NoteMatchKind.fuzzy),
      ('Einkaufslisten', 'Ideen/Einkaufsliste.md', NoteMatchKind.fuzzy),
      // Phonetisch (B6 auf dem Gerät mit whisper-base).
      ('Wandel Intest', 'Wendelin-Test.md', NoteMatchKind.phonetic),
      ('Wendeline Test', 'Wendelin-Test.md', NoteMatchKind.phonetic),
      ('Maltha 2026', 'Reisen/Malta 2026.md', NoteMatchKind.phonetic),
    ]) {
      test('„$query“ → $path (${kind.name})', () async {
        // Die zweite Wendelin-Test-Notiz nur für exakte Treffer, sonst
        // ist die Suche mehrdeutig.
        final env = _env(
          kind == NoteMatchKind.exact
              ? vault
              : vault.where((f) => !f.startsWith('Archiv/Wendelin')),
        );
        expect(await _resolve(env, query), NoteResolution(path, kind));
      });
    }

    test('zwei gefaltet gleiche Titel: mehrdeutig, nicht phonetisch', () async {
      final env = _env(vault);
      final e = await _fails(env, 'Wendelin_Test');
      expect(e.message, startsWith('Mehrdeutig'));
    });

    test('approximate nur bei fuzzy und phonetic', () {
      expect(
        [
          for (final k in NoteMatchKind.values)
            if (NoteResolution('a.md', k).approximate) k,
        ],
        [NoteMatchKind.fuzzy, NoteMatchKind.phonetic],
      );
      expect(
        const NoteResolution('a.md', NoteMatchKind.exact).toString(),
        'NoteResolution(a.md, exact)',
      );
      expect(
        const NoteResolution('a.md', NoteMatchKind.exact).hashCode,
        const NoteResolution('a.md', NoteMatchKind.exact).hashCode,
      );
    });

    test('resolveNote liefert weiter nur den Pfad', () async {
      final env = _env(['Wendelin-Test.md']);
      expect(
        await env.resolveNote('Wandel Intest', write: false, now: _now),
        'Wendelin-Test.md',
      );
    });

    test('Ordner im Namen grenzt auch die phonetische Suche ein', () async {
      final env = _env(['A/Wendelin-Test.md', 'B/Wendelin-Test.md']);
      expect(
        await _resolve(env, 'B/Wandel Intest'),
        const NoteResolution('B/Wendelin-Test.md', NoteMatchKind.phonetic),
      );
    });

    test('französisch mit dem einfachen Schlüssel', () async {
      final env = _env(['Courses.md', 'Recettes.md'], locale: 'fr');
      expect(
        await _resolve(env, 'Coursses'),
        const NoteResolution('Courses.md', NoteMatchKind.phonetic),
      );
    });
  });

  group('Rückfrage mit Vorschlag (B6 c)', () {
    test('Schreibzugriff fragt bei phonetic immer nach', () async {
      final env = _env(['Wendelin-Test.md', 'Andere.md']);
      final e = await _fails(env, 'Wandel Intest', write: true);
      expect(e.kind, PortErrorKind.rejected);
      expect(e.message, contains('Meinst du die Notiz'));
      expect(e.message, contains('<vault_names>["Wendelin-Test.md"]'));
      expect(e.message, contains('Bitte nachfragen'));
      expect(e.message, isNot(contains('gibt es nicht.')));
    });

    test('mehrere starke Kandidaten: höchstens drei nennen', () async {
      final env = _env([
        'A/Wendelin-Test.md',
        'B/Wendelin-Test.md',
        'C/Wendelin-Test.md',
        'D/Wendelin-Test.md',
      ]);
      final e = await _fails(env, 'Wandel Intest');
      expect(e.message, contains('eine der Notizen'));
      expect(
        e.message,
        contains(
          '["A/Wendelin-Test.md","B/Wendelin-Test.md","C/Wendelin-Test.md"]',
        ),
      );
      expect(e.message, isNot(contains('D/Wendelin-Test.md')));
    });

    test('nur schwacher Kandidat: lesen fragt auch nach', () async {
      // Drei Zeichen Abstand, anderer Schlüssel: kein starker Treffer.
      final env = _env(['Wendelin-Test.md']);
      final e = await _fails(env, 'Wendelin-Tesla');
      expect(e.message, contains('Meinst du die Notiz'));
    });

    test('nichts Ähnliches: gibt es nicht', () async {
      final env = _env(['Wendelin-Test.md']);
      final e = await _fails(env, 'Gartenplanung');
      expect(e.kind, PortErrorKind.notFound);
      expect(e.message, contains('gibt es nicht'));
      expect(e.message, contains('obsidian__search_notes'));
    });

    test('zu kurze Anfrage: keine phonetische Suche', () async {
      final env = _env(['Abc.md']);
      final e = await _fails(env, 'Abd');
      expect(e.kind, PortErrorKind.notFound);
    });
  });

  group('phoneticMatches', () {
    List<PhoneticMatch<String>> m(String q, List<String> names) =>
        phoneticMatches(q, names, (n) => [n]);

    test('stark vor schwach, dann nach Distanz', () {
      final r = m('Wandel Intest', [
        'Wendelin-Tests',
        'Wendelin-Test',
        'Wandel',
        'Wendelin-Tesla',
      ]);
      expect(r.map((x) => x.item), [
        'Wendelin-Test',
        'Wendelin-Tests',
        'Wendelin-Tesla',
      ]);
      expect(r.map((x) => (x.distance, x.strong)), [
        (1, true),
        (2, false),
        (3, false),
      ]);
    });

    test('gleich gute Kandidaten behalten die Reihenfolge', () {
      final r = m('Wandel Intest', ['B/Wendelin-Test', 'A/Wendelin-Test']);
      expect(r.map((x) => x.item), ['B/Wendelin-Test', 'A/Wendelin-Test']);
    });

    test('bester Name je Kandidat', () {
      final r = phoneticMatches('Wandel Intest', [
        'x',
      ], (_) => ['Gar nichts', 'Wendelin-Tests', 'Wendelin-Test']);
      expect(r.single.distance, 1);
      expect(r.single.strong, isTrue);
    });

    test('Grenzen der Distanz', () {
      expect(phoneticDistanceLimit(5), 1);
      expect(phoneticDistanceLimit(6), 2);
      expect(phoneticDistanceLimit(9), 2);
      expect(phoneticDistanceLimit(10), 3);
      expect(m('abc', ['abd']), isEmpty);
      expect(m('', ['']), isEmpty);
    });
  });

  test('read_note nennt die ähnlich klingende Notiz', () async {
    final vault = FakeVaultPort(
      files: {'Wendelin-Test.md': '## Status\noffen'},
    );
    final i = ObsidianIntegration(
      vault,
      FakeNoteIndex(),
      settings: () => const ObsidianSettings(vaultName: 'V'),
    );
    final read = i.tools.singleWhere((t) => t.name == 'obsidian__read_note');
    final o = await read.execute({'path': 'Wandel Intest'}, ctx());
    expect(o.isError, isFalse, reason: o.text);
    expect(o.text, contains('ähnlich klingende Notiz'));
    expect(o.text, contains('<vault_names>["Wendelin-Test.md"]</vault_names>'));
    expect(o.text, contains('match="phonetic"'));
    expect(o.text, contains('offen'));

    final exact = await read.execute({'path': 'Wendelin-Test'}, ctx());
    expect(exact.text, isNot(contains('Hinweis')));
    expect(exact.text, isNot(contains('match=')));

    final append = i.tools.singleWhere(
      (t) => t.name == 'obsidian__append_to_note',
    );
    final w = await append.execute({
      'path': 'Wandel Intest',
      'text': 'x',
    }, ctx());
    expect(w.isError, isTrue);
    expect(w.text, contains('Meinst du die Notiz'));
    expect(vault.writes, 0);
  });
}
