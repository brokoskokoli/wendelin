// Sucht in Testdateien nach Mustern, die unter Last flackern (WP96):
//
// * Wanduhr-Asserts: `Stopwatch` sowie `expect(…)` mit `DateTime.now()`
//   oder `watch.elapsed` (nicht `FakeAsync.elapsed`).
// * `runAsync(() => Future.delayed(…))` als Wartezeit, auch als Block
//   `runAsync(() async { …; await Future.delayed(…); })` mit davorstehenden
//   Anweisungen ohne eigene Klammern (stattdessen `pumpUntil` bzw.
//   `fakeAsync`).
//
// Gescannt werden nur Pfade mit `/test/`. `integration_test/` fällt dadurch
// nur implizit heraus (der Name enthält `_test/`, nicht `/test/`); Geräte-
// tests laufen nicht im Gate.
//
// Bestandstreffer stehen in `tool/flaky_allowlist.yaml`; die Liste
// schrumpft nur.
import 'dart:io';

/// Ein Muster mit Namen.
final _patterns = <String, RegExp>{
  'Stopwatch': RegExp(r'\bStopwatch\b'),
  'expect-Wanduhr': RegExp(
    r'\bexpect(Later)?\s*\([^;]*(DateTime\.now\(\)|\b(\w*[wW]atch|sw)\.elapsed\w*)',
    dotAll: true,
  ),
  'runAsync-delayed': RegExp(
    r'\brunAsync\s*(<[^>]*>)?\s*\(\s*\(\)\s*(async\s*)?'
    r'(?:=>\s*|\{\s*(?:[^{};]*;\s*)*)(await\s+)?Future(<[^>]*>)?\s*\.delayed\b',
    dotAll: true,
  ),
};

/// Treffer je Datei (Pfad mit `/`) und Anzahl; nur Dateien mit Treffern.
Map<String, int> scanFlaky(Iterable<File> files, {String root = '.'}) {
  final out = <String, int>{};
  for (final f in files) {
    final text = f.readAsStringSync();
    var n = 0;
    for (final re in _patterns.values) {
      n += re.allMatches(_stripComments(text)).length;
    }
    if (n > 0) out[_rel(f.path, root)] = n;
  }
  return out;
}

String _rel(String path, String root) {
  final p = path.replaceAll(r'\', '/');
  final r = root == '.' ? '' : '${root.replaceAll(r'\', '/')}/';
  var s = p.startsWith(r) ? p.substring(r.length) : p;
  if (s.startsWith('./')) s = s.substring(2);
  return s;
}

String _stripComments(String t) => t.replaceAll(RegExp(r'//[^\n]*'), '');

/// Testdateien (ohne integration_test und live) unter packages/, app/ und evals/ (ohne Build-Ordner).
List<File> testFiles({String root = '.'}) {
  final files = <File>[];
  for (final top in ['packages', 'app', 'evals']) {
    final d = Directory('$root/$top');
    if (!d.existsSync()) continue;
    for (final e in d.listSync(recursive: true, followLinks: false)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final p = e.path.replaceAll(r'\', '/');
      if (p.contains('/.dart_tool/') || p.contains('/build/')) continue;
      // Geräte- und Live-Tests laufen nicht im Gate.
      if (p.contains('/live/')) continue;
      if (p.contains('/test/')) {
        files.add(e);
      }
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// Liest `<pfad>: <anzahl>  # Grund` aus der Ausnahmeliste.
Map<String, int> parseFlakyAllowlist(String text) {
  final out = <String, int>{};
  for (final raw in text.split('\n')) {
    final line = raw.replaceFirst(RegExp(r'\s*#.*$'), '').trim();
    if (line.isEmpty) continue;
    final i = line.lastIndexOf(':');
    if (i < 0) continue;
    final n = int.tryParse(line.substring(i + 1).trim());
    if (n != null) out[line.substring(0, i).trim()] = n;
  }
  return out;
}

/// Abweichungen zwischen [found] und [allowed]: mehr Treffer als erlaubt
/// (neu) oder weniger (Eintrag senken bzw. entfernen).
List<String> compareFlaky(Map<String, int> found, Map<String, int> allowed) {
  final msgs = <String>[];
  for (final MapEntry(:key, :value) in found.entries) {
    final a = allowed[key] ?? 0;
    if (value > a) {
      msgs.add(
        '$key: $value Treffer (erlaubt $a). Keine Wanduhr-Asserts '
        '(Stopwatch, DateTime.now/elapsed in expect) und kein '
        'runAsync(Future.delayed) als Wartezeit: pumpUntil bzw. fakeAsync '
        'nutzen.',
      );
    }
  }
  for (final MapEntry(:key, :value) in allowed.entries) {
    final f = found[key] ?? 0;
    if (f < value) {
      msgs.add(
        '$key: nur noch $f Treffer, Eintrag in tool/flaky_allowlist.yaml '
        '${f == 0 ? 'entfernen' : 'auf $f senken'}.',
      );
    }
  }
  return msgs;
}
