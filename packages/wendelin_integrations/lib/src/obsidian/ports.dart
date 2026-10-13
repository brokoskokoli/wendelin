import 'package:meta/meta.dart';

/// One entry of a vault folder.
@immutable
final class VaultEntry {
  /// Creates an entry.
  const VaultEntry({
    required this.path,
    required this.isFolder,
    this.modifiedAt,
    this.size,
  });

  /// Vault-relative path (`Projekte/App.md`).
  final String path;

  /// Whether it is a folder.
  final bool isFolder;

  /// Last modification (files; `null` if unknown).
  final DateTime? modifiedAt;

  /// Size in bytes (files; `null` if unknown).
  final int? size;

  /// Last path segment.
  String get name => path.split('/').last;

  @override
  bool operator ==(Object other) =>
      other is VaultEntry &&
      other.path == path &&
      other.isFolder == isFolder &&
      other.modifiedAt == modifiedAt &&
      other.size == size;

  @override
  int get hashCode => Object.hash(path, isFolder, modifiedAt, size);

  @override
  String toString() => 'VaultEntry($path${isFolder ? '/' : ''})';
}

/// The Obsidian vault as a folder tree (Android: SAF tree URI with
/// persistent rights, WP18; iOS later: security-scoped bookmark).
///
/// Paths are vault-relative with `/` and already checked by `VaultPath`;
/// implementations check again and throw `PortException(rejected)` for
/// unsafe paths (`..`, absolute, hidden segments) and for symbolic links
/// that lead outside the vault. Must pass `vaultPortContract`.
abstract interface class VaultPort {
  /// Direct children of [folder] (`''` = vault root), in any order.
  /// Throws `PortException(notFound)` if the folder does not exist.
  Future<List<VaultEntry>> list(String folder);

  /// The file as UTF-8 text, byte for byte (BOM, line endings). Throws
  /// `PortException(notFound)` if it does not exist.
  Future<String> read(String path);

  /// Replaces the file content **atomically** (readers see the old or the
  /// new content, never a mix); creates the file and missing parent
  /// folders.
  Future<void> write(String path, String content);

  /// Creates a new file (and missing parent folders); throws
  /// `PortException(rejected)` if [path] already exists, without changing
  /// it.
  Future<void> create(String path, String content);

  /// Deletes the file. Throws `PortException(notFound)` if it does not
  /// exist.
  Future<void> delete(String path);

  /// Whether a file or folder exists at [path]; never throws for missing
  /// paths.
  Future<bool> exists(String path);

  /// Last modification time of the file; changes with every [write].
  /// Throws `PortException(notFound)` if it does not exist.
  Future<DateTime> modifiedAt(String path);

  /// Size of the file in bytes. Throws `PortException(notFound)` if it
  /// does not exist.
  Future<int> size(String path);
}

/// A search hit of the [NoteIndexPort].
@immutable
final class NoteHit {
  /// Creates a hit.
  const NoteHit({
    required this.path,
    required this.title,
    required this.snippet,
  });

  /// Vault-relative path.
  final String path;

  /// Note title (file name without `.md`).
  final String title;

  /// Short excerpt around the match (plain text, may be empty).
  final String snippet;

  @override
  bool operator ==(Object other) =>
      other is NoteHit &&
      other.path == path &&
      other.title == title &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(path, title, snippet);

  @override
  String toString() => 'NoteHit($path)';
}

/// Full-text index over the vault notes. The app wires it to
/// `NoteIndexRepository` (`wendelin_storage`, SQLite FTS5); must pass
/// `noteIndexPortContract`.
abstract interface class NoteIndexPort {
  /// Adds or replaces the note [path].
  Future<void> upsert(
    String path, {
    required String title,
    required String body,
    required DateTime modifiedAt,
  });

  /// Removes [path] from the index (no error if unknown).
  Future<void> remove(String path);

  /// The best [limit] notes for [query], best first: words are matched as
  /// prefixes, case and diacritics are ignored, title matches rank above
  /// body matches. Empty for blank queries; never throws for special
  /// characters.
  Future<List<NoteHit>> search(String query, {int limit = 10});

  /// All indexed paths with the modification time they were indexed at.
  Future<Map<String, DateTime>> knownFiles();
}
