import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  late FakeVaultPort vault;
  late FakeNoteIndex index;

  setUp(() {
    vault = FakeVaultPort(
      files: {
        'A.md': 'Apfel',
        'Ordner/B.md': 'Birne',
        'Ordner/Tief/C.md': 'Citrone',
        'Bild.png': 'binär',
        'Notiz.MD': 'groß geschrieben',
        '.obsidian/workspace.md': 'nein',
        '.trash/alt.md': 'nein',
        'Ordner/.versteckt/x.md': 'nein',
      },
    );
    index = FakeNoteIndex();
  });

  int reads() => vault.methodCalls.where((m) => m == 'read').length;

  test('indiziert nur .md außerhalb versteckter Ordner, mit Titel', () async {
    final r = await NoteIndexer(vault, index).sync();
    expect(index.notes.keys.toSet(), {
      'A.md',
      'Ordner/B.md',
      'Ordner/Tief/C.md',
      'Notiz.MD',
    });
    expect(index.notes['Ordner/Tief/C.md']!.title, 'C');
    expect(index.notes['Notiz.MD']!.title, 'Notiz');
    expect(index.notes['A.md']!.modifiedAt, vault.modified['A.md']);
    expect(r.indexed, 4);
    expect(r.complete, isTrue);
    expect(r.toString(), contains('indexed: 4'));
  });

  test(
    'inkrementell: nur Geändertes wird gelesen, Gelöschtes entfernt',
    () async {
      final indexer = NoteIndexer(vault, index);
      await indexer.sync();
      vault.methodCalls.clear();
      final idle = await indexer.sync();
      expect(reads(), 0);
      expect(idle.indexed, 0);

      vault.touch('Ordner/B.md', 'Banane');
      vault.files.remove('A.md');
      vault.methodCalls.clear();
      final r = await indexer.sync();
      expect(reads(), 1);
      expect(r.indexed, 1);
      expect(r.removed, 1);
      expect(index.notes['Ordner/B.md']!.body, 'Banane');
      expect(index.notes.containsKey('A.md'), isFalse);
    },
  );

  test('begrenzt je Lauf, neueste zuerst', () async {
    final indexer = NoteIndexer(vault, index, maxFilesPerRun: 2);
    final r = await indexer.sync();
    expect(r.indexed, 2);
    expect(r.pending, 2);
    // Die zuletzt geänderten Dateien kommen zuerst.
    expect(index.notes.keys.toSet(), {'Notiz.MD', 'Ordner/Tief/C.md'});
    final second = await indexer.sync();
    expect(second.pending, 0);
    expect(index.notes, hasLength(4));
  });

  test(
    'nicht lesbare Dateien werden übersprungen und später erneut versucht',
    () async {
      final indexer = NoteIndexer(vault, index);
      vault.failNext('read');
      final r = await indexer.sync();
      expect(r.failed, 1);
      expect(index.notes, hasLength(3));
      final again = await indexer.sync();
      expect(again.indexed, 1);
      expect(index.notes, hasLength(4));
    },
  );

  test('große Dateien nur mit Titel, lange Texte gekürzt', () async {
    vault.touch('Riesig.md', 'x' * 50);
    vault.touch('Lang.md', 'y' * 30);
    await NoteIndexer(
      vault,
      index,
      maxFileBytes: 40,
      maxIndexedChars: 20,
    ).sync();
    expect(index.notes['Riesig.md']!.body, '');
    expect(index.notes['Riesig.md']!.title, 'Riesig');
    expect(index.notes['Lang.md']!.body, 'y' * 20);
    expect(index.notes['A.md']!.body, 'Apfel');
  });

  test('zu viele Einträge: unvollständig, nichts wird entfernt', () async {
    await index.upsert(
      'Weg.md',
      title: 'Weg',
      body: '',
      modifiedAt: DateTime.utc(2020),
    );
    final r = await NoteIndexer(vault, index, maxEntries: 3).sync();
    expect(r.complete, isFalse);
    expect(r.removed, 0);
    expect(index.notes.containsKey('Weg.md'), isTrue);
  });

  test('schreibt in Stapeln über upsertAll', () async {
    final big = FakeVaultPort(
      files: {for (var i = 0; i < 120; i++) 'n$i.md': 'x'},
    );
    final r = await NoteIndexer(big, index).sync();
    expect(r.indexed, 120);
    expect(index.batches, 3);
    expect(index.methodCalls.where((m) => m == 'upsert'), isEmpty);
  });

  test('gleichzeitige Läufe teilen sich einen', () async {
    vault.delay = const Duration(milliseconds: 1);
    final indexer = NoteIndexer(vault, index);
    final runs = await Future.wait([indexer.sync(), indexer.sync()]);
    expect(identical(runs[0], runs[1]), isTrue);
    expect(reads(), 4);
  });

  test('Einträge ohne Zeit und Größe werden nachgefragt', () async {
    final port = _BareListPort(vault);
    await NoteIndexer(port, index).sync();
    expect(index.notes, hasLength(4));
    expect(vault.methodCalls, containsAll(['modifiedAt', 'size']));
  });
}

/// Lists entries without modification time and size (like a minimal SAF
/// query).
final class _BareListPort implements VaultPort {
  _BareListPort(this.inner);

  final FakeVaultPort inner;

  @override
  Future<List<VaultEntry>> list(String folder) async => [
    for (final e in await inner.list(folder))
      VaultEntry(path: e.path, isFolder: e.isFolder),
  ];

  @override
  Future<String> read(String path) => inner.read(path);

  @override
  Future<DateTime> modifiedAt(String path) => inner.modifiedAt(path);

  @override
  Future<int> size(String path) => inner.size(path);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
