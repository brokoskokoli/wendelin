import '../common/port_exception.dart';

/// Vault-relative paths: normalization and the safety rules every tool and
/// port applies before touching a file.
///
/// A valid path uses `/` as separator, has no empty, `.` or `..` segments,
/// does not start with `/`, `~`, a drive letter or a URI scheme, contains
/// no backslash or control character and no hidden segment (starting with
/// `.`, e.g. `.obsidian/`, `.trash/`, `.git/`) – also not percent-encoded.
abstract final class VaultPath {
  /// Longest accepted path (characters).
  static const maxLength = 1024;

  /// Longest accepted path segment (characters).
  static const maxSegment = 255;

  /// The vault root.
  static const root = '';

  /// Normalizes [input] (trims, collapses `//`, drops `.` segments and a
  /// trailing `/`). Throws `PortException(rejected)` for unsafe paths; the
  /// root (empty path) only with [allowRoot].
  static String normalize(String input, {bool allowRoot = false}) {
    final raw = input.trim();
    String reject(String why) =>
        throw PortException(PortErrorKind.rejected, 'Pfad „$raw“: $why');
    if (raw.length > maxLength) reject('zu lang');
    if (raw.contains('\\')) reject('bitte „/“ statt „\\“ verwenden');
    if (raw.runes.any((r) => r < 0x20 || r == 0x7F)) {
      reject('enthält Steuerzeichen');
    }
    if (raw.startsWith('/') || raw.startsWith('~')) {
      reject('nur Pfade innerhalb des Vaults (relativ)');
    }
    if (RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(raw)) {
      reject('nur Pfade innerhalb des Vaults (keine Adresse oder Laufwerk)');
    }
    final segments = <String>[];
    for (final s in raw.split('/')) {
      final seg = s.trim();
      if (seg.isEmpty || seg == '.') continue;
      final decoded = _decoded(seg);
      if (seg == '..' || decoded == '..' || decoded == '.') {
        reject('„..“ ist nicht erlaubt');
      }
      if (seg.startsWith('.') || decoded.startsWith('.')) {
        reject(
          seg.toLowerCase() == '.obsidian' ||
                  decoded.toLowerCase() == '.obsidian'
              ? 'der Obsidian-Konfigurationsordner ist gesperrt'
              : 'versteckte Dateien und Ordner sind gesperrt',
        );
      }
      if (seg.length > maxSegment) reject('Name zu lang');
      segments.add(seg);
    }
    if (segments.isEmpty && !allowRoot) reject('leer');
    return segments.join('/');
  }

  /// [normalize] for a note: appends `.md` unless the path ends with it
  /// (case-insensitive).
  static String note(String input) {
    final p = normalize(input);
    return p.toLowerCase().endsWith('.md') ? p : '$p.md';
  }

  /// Like [note], but also rejects characters Obsidian does not allow in
  /// file names (`* " < > : | ?`) and names ending with a dot or space;
  /// used when a note is created.
  static String newNote(String input) {
    final p = note(input);
    final bad = RegExp(r'[*"<>:|?]');
    for (final seg in p.split('/')) {
      if (bad.hasMatch(seg)) {
        throw PortException(
          PortErrorKind.rejected,
          'Name „$seg“: Zeichen * " < > : | ? sind nicht erlaubt',
        );
      }
    }
    return p;
  }

  /// Last segment of [path].
  static String name(String path) => path.split('/').last;

  /// [name] without a `.md` extension (the note title in Obsidian).
  static String title(String path) {
    final n = name(path);
    return n.toLowerCase().endsWith('.md') ? n.substring(0, n.length - 3) : n;
  }

  /// Folder of [path] (empty for the root).
  static String parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? root : path.substring(0, i);
  }

  /// [folder] and [name] joined.
  static String join(String folder, String name) =>
      folder.isEmpty ? name : '$folder/$name';

  /// Whether some segment of [path] is hidden (starts with `.`).
  static bool isHidden(String path) =>
      path.split('/').any((s) => s.startsWith('.'));

  static String _decoded(String seg) {
    try {
      return Uri.decodeComponent(seg).trim();
    } on ArgumentError {
      return seg;
    }
  }
}
