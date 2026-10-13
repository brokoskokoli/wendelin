import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// [NoteIndexPort] on the `NoteIndexRepository` of `wendelin_storage`
/// (SQLite FTS5). Storage must not import integrations, so the two
/// interfaces mirror each other and this adapter only maps the hit type
/// (same pattern as `RepositoryMemoryPort`).
final class RepositoryNoteIndexPort implements NoteIndexPort {
  /// Creates the port on [repository].
  RepositoryNoteIndexPort(this.repository);

  /// Storage repository.
  final NoteIndexRepository repository;

  @override
  Future<void> upsert(
    String path, {
    required String title,
    required String body,
    required DateTime modifiedAt,
  }) =>
      repository.upsert(path, title: title, body: body, modifiedAt: modifiedAt);

  @override
  Future<void> upsertAll(List<IndexedNote> notes) =>
      repository.upsertAll(notes);

  @override
  Future<void> remove(String path) => repository.remove(path);

  @override
  Future<List<NoteHit>> search(String query, {int limit = 10}) async => [
    for (final h in await repository.search(query, limit: limit))
      NoteHit(path: h.path, title: h.title, snippet: h.snippet),
  ];

  @override
  Future<Map<String, DateTime>> knownFiles() => repository.knownFiles();
}
