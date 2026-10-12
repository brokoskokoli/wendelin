import 'package:meta/meta.dart';

/// Category of a memory entry (concept: person, vorliebe, fakt, projekt).
enum MemoryCategory {
  /// A person and facts about them.
  person,

  /// A preference of the user.
  preference,

  /// A general fact.
  fact,

  /// A project the user works on.
  project,
}

/// One long-term memory entry.
@immutable
final class MemoryEntry {
  /// Creates an entry.
  const MemoryEntry({
    required this.id,
    required this.text,
    required this.category,
    required this.source,
    required this.createdAt,
    required this.lastUsedAt,
  });

  /// Stable id.
  final String id;

  /// The remembered text.
  final String text;

  /// Category.
  final MemoryCategory category;

  /// Where the entry came from, e.g. `user` ("merk dir …") or
  /// `suggestion` (confirmed end-of-conversation suggestion).
  final String source;

  /// When the entry was saved.
  final DateTime createdAt;

  /// When the entry was last returned by a search (or saved).
  final DateTime lastUsedAt;

  @override
  bool operator ==(Object other) =>
      other is MemoryEntry &&
      other.id == id &&
      other.text == text &&
      other.category == category &&
      other.source == source &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt;

  @override
  int get hashCode =>
      Object.hash(id, text, category, source, createdAt, lastUsedAt);

  @override
  String toString() => 'MemoryEntry($id, ${category.name}, $text)';
}
