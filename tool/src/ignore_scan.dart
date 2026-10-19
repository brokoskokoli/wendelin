// Zählt `// ignore:` und `// ignore_for_file:` je Regel (WP109, Ratsche).
// Erzeugter Code (siehe kindOf) und Build-Ordner sind ausgenommen.
import 'dart:io';

import 'size_rules.dart';

final _ignore = RegExp(r'^//\s*(ignore_for_file|ignore)\s*:\s*(.*)$');
final _rule = RegExp(r'^[a-z][a-z0-9_]*(=[a-z0-9_]+)?');
final _wholeRule = RegExp(r'^[a-z][a-z0-9_]*(=[a-z0-9_]+)?$');

/// Zählt die Ignores in [text]: Schlüssel `ignore/<regel>` bzw.
/// `ignore_for_file/<regel>`.
Map<String, int> countIgnores(String text) {
  final out = <String, int>{};
  for (final line in text.split('\n')) {
    // Nur das erste `//` der Zeile zählt (kein Treffer in Doku-Kommentaren).
    final at = line.indexOf('//');
    if (at < 0) continue;
    final m = _ignore.firstMatch(line.substring(at));
    if (m == null) continue;
    // Regeln stehen kommagetrennt vorn; erst ein Teil, der keine Regel ist
    // (Begründung als Fließtext), beendet die Liste. Der erste Teil darf
    // eine Begründung nach der Regel tragen.
    for (final (i, part) in m.group(2)!.split(',').indexed) {
      final t = part.trim();
      final r = i == 0 || _wholeRule.hasMatch(t) ? _rule.firstMatch(t) : null;
      if (r == null) break;
      final key = '${m.group(1)}/${r.group(0)}';
      out[key] = (out[key] ?? 0) + 1;
    }
  }
  return out;
}

/// Erzeugter Code: Ordner `gen`/`generated`, `*_generated*.dart`, `*.freezed.dart`.
bool isGenerated(String path) {
  final segs = path.split('/');
  return segs.contains('gen') ||
      segs.contains('generated') ||
      segs.last.contains('_generated') ||
      segs.last.endsWith('.freezed.dart');
}

/// Zählt über alle Dart-Dateien unter [roots] (ohne erzeugten Code).
Map<String, int> scanIgnores({
  String root = '.',
  List<String> roots = const ['packages', 'app', 'evals', 'tool'],
}) {
  final out = <String, int>{};
  const skip = {'build', '.dart_tool', '.gradle', 'Pods', '.git', 'ios'};
  void walk(Directory dir, String rel) {
    for (final e in dir.listSync(followLinks: false)) {
      final name = e.path.split('/').last;
      final p = '$rel/$name';
      if (e is Directory) {
        if (!skip.contains(name)) walk(e, p);
      } else if (e is File && name.endsWith('.dart')) {
        if (kindOf(p) == FileKind.excluded || isGenerated(p)) continue;
        countIgnores(e.readAsStringSync()).forEach((k, v) {
          out[k] = (out[k] ?? 0) + v;
        });
      }
    }
  }

  for (final r in roots) {
    final d = Directory('$root/$r');
    if (d.existsSync()) walk(d, r);
  }
  return out;
}
