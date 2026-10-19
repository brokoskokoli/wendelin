// Pfadangaben in Markdown finden und gegen die Dateien im Repo auflösen
// (für `tool/check_docs.dart`).

/// Eine Pfadangabe mit Zeilennummer.
typedef PathRef = ({String path, int line});

final _code = RegExp(r'`([^`\n]+)`');
final _pathLike = RegExp(r'^[\w.\-/]+$');
final _ext = RegExp(r'\.(dart|kt|kts|md|yaml|yml|sh|xml|json|png)$');
final _host = RegExp(r'^[\w\-]+\.(com|org|io|dev|net|app)(/|$)');
final _lineSuffix = RegExp(r':\d+(-\d+)?$');

/// Alle Angaben in Backticks, die wie ein Pfad aussehen: mit Endung
/// (`.dart`, `.kt`, `.md`, …) oder mit `/`. Platzhalter (`<…>`, `*`, `…`)
/// sowie absolute Pfade und Web-Adressen werden übersprungen, `package:`-URIs
/// auf den Ordner abgebildet und `:<zeile>` entfernt.
List<PathRef> pathRefs(String markdown) {
  final refs = <PathRef>[];
  for (final (i, line) in markdown.split('\n').indexed) {
    for (final m in _code.allMatches(line)) {
      var p = m.group(1)!.trim();
      if (p.startsWith('package:')) p = _packageUri(p) ?? '';
      p = p.replaceFirst(_lineSuffix, '');
      if (p.isEmpty || !_pathLike.hasMatch(p)) continue;
      // Schalter, absolute Pfade und Web-Adressen sind keine Repo-Pfade.
      if (p.startsWith('-') || p.startsWith('/') || _host.hasMatch(p)) {
        continue;
      }
      if (!_ext.hasMatch(p) && !p.contains('/')) continue;
      refs.add((path: p, line: i + 1));
    }
  }
  return refs;
}

final _link = RegExp(r'\[[^\]\n]*\]\(([^)\s]+)\)');

/// Relative Markdown-Links `[Text](pfad#anker)` (ohne Web-Adressen und reine
/// Anker), Anker abgeschnitten.
List<PathRef> linkRefs(String markdown) {
  final refs = <PathRef>[];
  for (final (i, line) in markdown.split('\n').indexed) {
    for (final m in _link.allMatches(line)) {
      var p = m.group(1)!;
      if (p.startsWith('#') || RegExp(r'^[a-z]+:').hasMatch(p)) continue;
      final h = p.indexOf('#');
      if (h >= 0) p = p.substring(0, h);
      if (p.isEmpty) continue;
      refs.add((path: p, line: i + 1));
    }
  }
  return refs;
}

/// `package:wendelin_core/fakes.dart` → `packages/wendelin_core/lib/fakes.dart`.
String? _packageUri(String uri) {
  final m = RegExp(r'^package:(wendelin_\w+)/(.+)$').firstMatch(uri);
  if (m == null) return null;
  return 'packages/${m.group(1)}/lib/${m.group(2)}';
}

/// Dateien und Ordner des Repos für die Auflösung.
final class RepoIndex {
  /// Baut den Index aus Dateipfaden relativ zum Root.
  RepoIndex(Iterable<String> files) {
    for (final f in files) {
      _files.add(f);
      final parts = f.split('/');
      for (var i = 1; i < parts.length; i++) {
        _dirs.add(parts.take(i).join('/'));
      }
    }
  }

  final _files = <String>{};
  final _dirs = <String>{};

  /// [path] existiert relativ zum Root, relativ zu [docDir] oder als
  /// eindeutiges Ende eines Pfads im Repo (`di/providers.dart`).
  bool resolves(String path, {String docDir = ''}) {
    final p = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    bool exists(String q) => _files.contains(q) || _dirs.contains(q);
    if (exists(p)) return true;
    if (docDir.isNotEmpty && exists(_normalize('$docDir/$p'))) return true;
    return _files.any((f) => f.endsWith('/$p')) ||
        _dirs.any((d) => d.endsWith('/$p'));
  }

  /// Ein relativer Link zeigt von [docDir] aus auf eine Datei oder einen Ordner.
  bool resolvesLink(String path, {String docDir = ''}) {
    final p = _normalize(docDir.isEmpty ? path : '$docDir/$path');
    final q = p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    return _files.contains(q) || _dirs.contains(q);
  }

  static String _normalize(String path) {
    final out = <String>[];
    for (final s in path.split('/')) {
      if (s == '..' && out.isNotEmpty) {
        out.removeLast();
      } else if (s != '.') {
        out.add(s);
      }
    }
    return out.join('/');
  }
}
