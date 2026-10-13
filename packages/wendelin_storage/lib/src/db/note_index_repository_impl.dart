import 'package:drift/drift.dart';

import '../model/note_search_hit.dart';
import '../repositories/repositories.dart';
import 'database.dart';
import 'memory_repository_impl.dart' show ftsQuery;

/// drift implementation of [NoteIndexRepository] on `note_files` +
/// `note_fts` (FTS5, bm25 with weights path 2, title 10, body 1).
final class DriftNoteIndexRepository implements NoteIndexRepository {
  /// bm25 weight of the title column (body = 1).
  static const titleWeight = 10.0;

  /// bm25 weight of the path column (folder names).
  static const pathWeight = 2.0;

  /// Creates the repository.
  DriftNoteIndexRepository(this._db);

  final WendelinDatabase _db;

  @override
  Future<void> upsert(
    String path, {
    required String title,
    required String body,
    required DateTime modifiedAt,
  }) => upsertAll([
    (path: path, title: title, body: body, modifiedAt: modifiedAt),
  ]);

  @override
  Future<void> upsertAll(List<NoteIndexEntry> notes) async {
    if (notes.isEmpty) return;
    await _db.transaction(() async {
      for (final n in notes) {
        await _db.customStatement('DELETE FROM note_fts WHERE path = ?1', [
          n.path,
        ]);
        await _db.customStatement(
          'INSERT INTO note_fts (path, title, body) VALUES (?1, ?2, ?3)',
          [n.path, n.title, n.body],
        );
        await _db
            .into(_db.noteFiles)
            .insertOnConflictUpdate(
              NoteFileRow(
                path: n.path,
                title: n.title,
                modifiedAt: n.modifiedAt,
              ),
            );
      }
    });
  }

  @override
  Future<void> remove(String path) => _db.transaction(() async {
    await _db.customStatement('DELETE FROM note_fts WHERE path = ?1', [path]);
    await (_db.delete(_db.noteFiles)..where((n) => n.path.equals(path))).go();
  });

  @override
  Future<List<NoteSearchHit>> search(String query, {int limit = 10}) async {
    final match = ftsQuery(query);
    if (match == null || limit <= 0) return const [];
    final rows = await _db
        .customSelect(
          "SELECT path, title, snippet(note_fts, 2, '', '', '…', 16) AS s "
          'FROM note_fts WHERE note_fts MATCH ?1 '
          'ORDER BY bm25(note_fts, $pathWeight, $titleWeight, 1.0), path '
          'LIMIT ?2',
          variables: [Variable.withString(match), Variable.withInt(limit)],
          readsFrom: {_db.noteFts},
        )
        .get();
    return [
      for (final r in rows)
        NoteSearchHit(
          path: r.read<String>('path'),
          title: r.read<String>('title'),
          snippet: r.read<String>('s').replaceAll(RegExp(r'\s+'), ' ').trim(),
        ),
    ];
  }

  @override
  Future<Map<String, DateTime>> knownFiles() async => {
    for (final r in await _db.select(_db.noteFiles).get()) r.path: r.modifiedAt,
  };

  @override
  Future<int> count() async {
    final c = _db.noteFiles.path.count();
    final q = _db.selectOnly(_db.noteFiles)..addColumns([c]);
    return (await q.getSingle()).read(c)!;
  }

  @override
  Future<void> clear() => _db.transaction(() async {
    await _db.customStatement('DELETE FROM note_fts');
    await _db.delete(_db.noteFiles).go();
  });
}
