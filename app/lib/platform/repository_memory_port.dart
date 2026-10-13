import 'package:wendelin_core/wendelin_core.dart'
    show PrivacyLevel, detectSensitiveContent;
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// [MemoryStorePort] on the `MemoryRepository` of `wendelin_storage`.
///
/// Both the integration's and the storage's protection rule apply: text is
/// checked with core's `detectSensitiveContent` first, and a
/// `SensitiveContentException` of the repository also becomes
/// `PortException(rejected)`.
///
/// The repository sets `lastUsedAt` to the creation time on save; the port
/// reports `null` until a search returned the entry (port contract).
final class RepositoryMemoryPort implements MemoryStorePort {
  /// Creates the port on [repository].
  RepositoryMemoryPort(this.repository);

  /// Storage repository.
  final MemoryRepository repository;

  @override
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
    PrivacyLevel? privacyFloor,
  }) async {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'darf nicht leer sein');
    }
    final finding = detectSensitiveContent(text);
    if (finding != null) {
      throw PortException(PortErrorKind.rejected, finding.reason);
    }
    try {
      final saved = await repository.save(
        text,
        category: _toStorage(category),
        source: source,
        privacyFloor: privacyFloor,
      );
      return _toPort(saved);
    } on SensitiveContentException catch (e) {
      throw PortException(PortErrorKind.rejected, e.message);
    }
  }

  @override
  Future<List<MemoryEntry>> search(String query, {int limit = 5}) async {
    final hits = await repository.search(query, limit: limit);
    return [for (final e in hits) _toPort(e, used: true)];
  }

  @override
  Future<MemoryEntry> forget(String id) async {
    final entry = await repository.get(id);
    if (entry == null || !await repository.forget(id)) {
      throw PortException(
        PortErrorKind.notFound,
        'Eintrag „$id“ gibt es nicht',
      );
    }
    return _toPort(entry);
  }

  @override
  Future<List<MemoryEntry>> list() async => [
    for (final e in await repository.list()) _toPort(e),
  ];

  static MemoryEntry _toPort(StoredMemory e, {bool used = false}) =>
      MemoryEntry(
        id: e.id,
        text: e.text,
        category: _toPortCategory(e.category),
        source: e.source,
        createdAt: e.createdAt,
        lastUsedAt: used || e.lastUsedAt.isAfter(e.createdAt)
            ? e.lastUsedAt
            : null,
        privacyFloor: e.privacyFloor,
      );

  static StoredMemoryCategory _toStorage(MemoryCategory c) => switch (c) {
    MemoryCategory.person => StoredMemoryCategory.person,
    MemoryCategory.preference => StoredMemoryCategory.preference,
    MemoryCategory.fact => StoredMemoryCategory.fact,
    MemoryCategory.project => StoredMemoryCategory.project,
  };

  static MemoryCategory _toPortCategory(StoredMemoryCategory c) => switch (c) {
    StoredMemoryCategory.person => MemoryCategory.person,
    StoredMemoryCategory.preference => MemoryCategory.preference,
    StoredMemoryCategory.fact => MemoryCategory.fact,
    StoredMemoryCategory.project => MemoryCategory.project,
  };
}
