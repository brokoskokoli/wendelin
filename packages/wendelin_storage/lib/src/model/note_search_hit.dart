import 'package:meta/meta.dart';

/// A hit of `NoteIndexRepository.search`.
@immutable
final class NoteSearchHit {
  /// Creates a hit.
  const NoteSearchHit({
    required this.path,
    required this.title,
    required this.snippet,
  });

  /// Vault-relative path of the note.
  final String path;

  /// Note title.
  final String title;

  /// Short plain-text excerpt around the match.
  final String snippet;

  @override
  bool operator ==(Object other) =>
      other is NoteSearchHit &&
      other.path == path &&
      other.title == title &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(path, title, snippet);

  @override
  String toString() => 'NoteSearchHit($path)';
}
