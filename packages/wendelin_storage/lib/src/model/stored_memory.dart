import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart' show PrivacyLevel;

/// Category of a memory entry (concept: person, vorliebe, fakt, projekt).
enum StoredMemoryCategory {
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
final class StoredMemory {
  /// Creates an entry.
  const StoredMemory({
    required this.id,
    required this.text,
    required this.category,
    required this.source,
    required this.createdAt,
    required this.lastUsedAt,
    this.privacyFloor,
  });

  /// Stable id.
  final String id;

  /// The remembered text.
  final String text;

  /// Category.
  final StoredMemoryCategory category;

  /// Where the entry came from, e.g. `user` ("merk dir …") or
  /// `suggestion` (confirmed end-of-conversation suggestion).
  final String source;

  /// When the entry was saved.
  final DateTime createdAt;

  /// When the entry was last returned by a search (or saved).
  final DateTime lastUsedAt;

  /// Set when saved by a private run: only targets with at least this
  /// privacy level may see the entry (schema v3).
  final PrivacyLevel? privacyFloor;

  @override
  bool operator ==(Object other) =>
      other is StoredMemory &&
      other.id == id &&
      other.text == text &&
      other.category == category &&
      other.source == source &&
      other.createdAt == createdAt &&
      other.lastUsedAt == lastUsedAt &&
      other.privacyFloor == privacyFloor;

  @override
  int get hashCode => Object.hash(
    id,
    text,
    category,
    source,
    createdAt,
    lastUsedAt,
    privacyFloor,
  );

  @override
  String toString() => 'StoredMemory($id, ${category.name}, $text)';
}
