import 'package:wendelin_core/wendelin_core.dart' show detectSensitiveContent;
import 'package:wendelin_integrations/wendelin_integrations.dart' as wi;
import 'package:wendelin_storage/wendelin_storage.dart' as st;

/// [wi.MemoryStorePort] on the `MemoryRepository` of `wendelin_storage`.
///
/// Both the integration's and the storage's protection rule apply: text is
/// checked with core's `detectSensitiveContent` first, and a
/// `SensitiveContentException` of the repository also becomes
/// `PortException(rejected)`.
///
/// The repository sets `lastUsedAt` to the creation time on save; the port
/// reports `null` until a search returned the entry (port contract).
final class RepositoryMemoryPort implements wi.MemoryStorePort {
  /// Creates the port on [repository].
  RepositoryMemoryPort(this.repository);

  /// Storage repository.
  final st.MemoryRepository repository;

  @override
  Future<wi.MemoryEntry> save(
    String text, {
    required wi.MemoryCategory category,
    required String source,
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'darf nicht leer sein');
    }
    final finding = detectSensitiveContent(text);
    if (finding != null) {
      throw wi.PortException(wi.PortErrorKind.rejected, finding.reason);
    }
    try {
      final saved = await repository.save(
        text,
        category: _toStorage(category),
        source: source,
      );
      return _toPort(saved);
    } on st.SensitiveContentException catch (e) {
      throw wi.PortException(wi.PortErrorKind.rejected, e.message);
    }
  }

  @override
  Future<List<wi.MemoryEntry>> search(String query, {int limit = 5}) async {
    final hits = await repository.search(query, limit: limit);
    return [for (final e in hits) _toPort(e, used: true)];
  }

  @override
  Future<wi.MemoryEntry> forget(String id) async {
    final entry = await repository.get(id);
    if (entry == null || !await repository.forget(id)) {
      throw wi.PortException(
        wi.PortErrorKind.notFound,
        'Eintrag „$id“ gibt es nicht',
      );
    }
    return _toPort(entry);
  }

  @override
  Future<List<wi.MemoryEntry>> list() async => [
    for (final e in await repository.list()) _toPort(e),
  ];

  static wi.MemoryEntry _toPort(st.MemoryEntry e, {bool used = false}) =>
      wi.MemoryEntry(
        id: e.id,
        text: e.text,
        category: _toPortCategory(e.category),
        source: e.source,
        createdAt: e.createdAt,
        lastUsedAt: used || e.lastUsedAt.isAfter(e.createdAt)
            ? e.lastUsedAt
            : null,
      );

  static st.MemoryCategory _toStorage(wi.MemoryCategory c) => switch (c) {
    wi.MemoryCategory.person => st.MemoryCategory.person,
    wi.MemoryCategory.preference => st.MemoryCategory.preference,
    wi.MemoryCategory.fact => st.MemoryCategory.fact,
    wi.MemoryCategory.project => st.MemoryCategory.project,
  };

  static wi.MemoryCategory _toPortCategory(st.MemoryCategory c) => switch (c) {
    st.MemoryCategory.person => wi.MemoryCategory.person,
    st.MemoryCategory.preference => wi.MemoryCategory.preference,
    st.MemoryCategory.fact => wi.MemoryCategory.fact,
    st.MemoryCategory.project => wi.MemoryCategory.project,
  };
}
