import 'package:drift/drift.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../model/memory_entry.dart';
import '../repositories/repositories.dart';
import '../sensitive_content.dart';
import 'database.dart';

/// drift implementation of [MemoryRepository] with FTS5 search.
final class DriftMemoryRepository implements MemoryRepository {
  /// Creates the repository.
  DriftMemoryRepository(this._db, this._clock, this._ids);

  final WendelinDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;

  @override
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
  }) async {
    checkNotSensitive(text);
    final now = _clock.now();
    final row = MemoryRow(
      id: _ids.next(),
      body: text,
      category: category,
      source: source,
      createdAt: now,
      lastUsedAt: now,
    );
    await _db.into(_db.memoryEntries).insert(row);
    return _entry(row);
  }

  @override
  Future<MemoryEntry?> update(
    String id, {
    String? text,
    MemoryCategory? category,
  }) async {
    if (text != null) checkNotSensitive(text);
    await (_db.update(_db.memoryEntries)..where((m) => m.id.equals(id))).write(
      MemoryEntriesCompanion(
        body: Value.absentIfNull(text),
        category: Value.absentIfNull(category),
      ),
    );
    return get(id);
  }

  @override
  Future<bool> forget(String id) async =>
      await (_db.delete(
        _db.memoryEntries,
      )..where((m) => m.id.equals(id))).go() >
      0;

  @override
  Future<MemoryEntry?> get(String id) async {
    final row = await (_db.select(
      _db.memoryEntries,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    return row == null ? null : _entry(row);
  }

  @override
  Future<List<MemoryEntry>> list({MemoryCategory? category}) async {
    final q = _db.select(_db.memoryEntries)
      ..orderBy([
        (m) => OrderingTerm.desc(m.createdAt),
        (m) => OrderingTerm.asc(m.id),
      ]);
    if (category != null) q.where((m) => m.category.equalsValue(category));
    return (await q.get()).map(_entry).toList();
  }

  @override
  Future<List<MemoryEntry>> search(String query, {int limit = 5}) async {
    final match = ftsQuery(query);
    if (match == null || limit <= 0) return const [];
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            'SELECT m.* FROM memory_fts f '
            'JOIN memory_entries m ON m.id = f.entry_id '
            'WHERE memory_fts MATCH ?1 '
            'ORDER BY bm25(memory_fts), m.last_used_at DESC '
            'LIMIT ?2',
            variables: [Variable.withString(match), Variable.withInt(limit)],
            readsFrom: {_db.memoryFts, _db.memoryEntries},
          )
          .asyncMap((r) => _db.memoryEntries.mapFromRow(r))
          .get();
      if (rows.isEmpty) return const <MemoryEntry>[];
      final now = _clock.now();
      final ids = [for (final r in rows) r.id];
      await (_db.update(_db.memoryEntries)..where((m) => m.id.isIn(ids))).write(
        MemoryEntriesCompanion(lastUsedAt: Value(now)),
      );
      return [for (final r in rows) _entry(r.copyWith(lastUsedAt: now))];
    });
  }

  @override
  Future<String> exportMarkdown() async {
    final entries = await list();
    final b = StringBuffer('# Gedächtnis\n');
    for (final category in MemoryCategory.values) {
      final inCategory = entries.where((e) => e.category == category).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (inCategory.isEmpty) continue;
      b.write('\n## ${_heading[category]}\n\n');
      for (final e in inCategory) {
        final text = e.text.replaceAll(RegExp(r'\s*\n\s*'), ' ');
        b.write('- $text (${e.source}, ${_date(e.createdAt)})\n');
      }
    }
    return b.toString();
  }

  static const _heading = {
    MemoryCategory.person: 'Personen',
    MemoryCategory.preference: 'Vorlieben',
    MemoryCategory.fact: 'Fakten',
    MemoryCategory.project: 'Projekte',
  };

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static MemoryEntry _entry(MemoryRow r) => MemoryEntry(
    id: r.id,
    text: r.body,
    category: r.category,
    source: r.source,
    createdAt: r.createdAt,
    lastUsedAt: r.lastUsedAt,
  );
}

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Turns free text into a safe FTS5 query: every word becomes a quoted
/// prefix term, terms are OR-ed. Returns `null` if [text] has no words.
String? ftsQuery(String text) {
  final words = _word.allMatches(text).map((m) => m.group(0)!).toSet();
  if (words.isEmpty) return null;
  return words.map((w) => '"$w"*').join(' OR ');
}
