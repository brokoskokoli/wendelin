// Größenregeln aus docs/ENGINEERING.md („Größen“) und ihre Auswertung
// gegen die Allowlist `tool/size_allowlist.yaml`. Reine Funktionen, damit
// die Selbsttests sie ohne Dateisystem prüfen können.
import 'size_scan.dart';

/// Art einer Datei für die Schwellen.
enum FileKind {
  /// Produktivcode (Dart unter lib/, tool/, Kotlin main).
  production,

  /// Fakes und Contract-Suites unter `lib/testing/`: nur Warnungen.
  testingLib,

  /// Tests (test/, integration_test/, androidTest/).
  test,

  /// Generiert oder Fixture: nicht gemessen.
  excluded,
}

/// Schwellen in Zeilen (Warnung ab „größer als“).
const prodWarn = 600, prodError = 800;

/// Schwellen für Testdateien.
const testWarn = 1000, testError = 1500;

/// Schwellen für Funktionen bzw. `build()`.
const fnWarn = 80, fnError = 150;

/// Warnschwelle für Klassen.
const classWarn = 400;

/// Ordnet einen Pfad (relativ zum Root, mit `/`) einer [FileKind] zu.
FileKind kindOf(String path) {
  final segs = path.split('/');
  if (path.endsWith('.g.dart') ||
      path.endsWith('.steps.dart') ||
      (segs.contains('test') && segs.contains('generated')) ||
      path.contains('/test/fixtures/')) {
    return FileKind.excluded;
  }
  if (segs.contains('test') ||
      segs.contains('integration_test') ||
      segs.contains('androidTest')) {
    return FileKind.test;
  }
  if (path.contains('/lib/testing/')) return FileKind.testingLib;
  return FileKind.production;
}

/// Messwerte einer Datei.
final class FileSize {
  /// Erstellt die Messwerte.
  const FileSize(
    this.path,
    this.lines, {
    this.functions = const [],
    this.classes = const [],
  });

  /// Pfad relativ zum Root.
  final String path;

  /// Zeilenzahl.
  final int lines;

  /// Funktionen (nur Produktivcode und lib/testing).
  final List<Measure> functions;

  /// Klassen (nur Produktivcode und lib/testing).
  final List<Measure> classes;

  /// Art der Datei.
  FileKind get kind => kindOf(path);
}

/// Ein Allowlist-Eintrag: Obergrenze und abbauendes Paket.
typedef AllowEntry = ({int limit, String ref});

/// Liest die Allowlist (`<pfad>[#<funktion>]: <zeilen>  # WPnn …`).
/// Fehler (Syntax, fehlender WP-Verweis) landen in [errors].
Map<String, AllowEntry> parseAllowlist(String text, List<String> errors) {
  final result = <String, AllowEntry>{};
  final entry = RegExp(r'^([^#\s][^:]*?)\s*:\s*(\d+)\s*(?:#\s*(.*))?$');
  for (final (i, raw) in text.split('\n').indexed) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final m = entry.firstMatch(line);
    if (m == null) {
      errors.add('size_allowlist.yaml:${i + 1}: unlesbar: $line');
      continue;
    }
    final ref = m.group(3) ?? '';
    if (!RegExp(r'\bWP\d+').hasMatch(ref)) {
      errors.add(
        'size_allowlist.yaml:${i + 1}: Verweis auf das abbauende Paket '
        '(# WPnn) fehlt',
      );
    }
    result[m.group(1)!] = (limit: int.parse(m.group(2)!), ref: ref);
  }
  return result;
}

/// Ergebnis der Prüfung.
final class SizeReport {
  /// Fehler (Gate rot).
  final errors = <String>[];

  /// Warnungen (nur Anzahl in der Gate-Zusammenfassung).
  final warnings = <String>[];
}

/// Prüft [files] gegen die Schwellen und die [allow]-Liste.
SizeReport evaluate(List<FileSize> files, Map<String, AllowEntry> allow) {
  final r = SizeReport();
  final seen = <String>{};

  void check(String key, int lines, int warn, int? error, String what) {
    final a = allow[key];
    if (a != null) seen.add(key);
    if (error != null && lines > error) {
      if (a == null) {
        r.errors.add(
          '$key: $lines Zeilen ($what > $error), nicht auf der Allowlist',
        );
      } else if (lines > a.limit) {
        r.errors.add(
          '$key: $lines Zeilen, gewachsen über die Allowlist-Grenze ${a.limit} (${a.ref})',
        );
      } else if (lines < a.limit) {
        r.warnings.add(
          '$key: $lines Zeilen, Allowlist-Grenze ${a.limit} auf $lines senken',
        );
      }
    } else if (a != null) {
      r.errors.add(
        '$key: $lines Zeilen, unter der Fehlerschwelle: Eintrag aus tool/size_allowlist.yaml entfernen',
      );
    }
    if (lines > warn && (error == null || lines <= error || a != null)) {
      r.warnings.add('$key: $lines Zeilen ($what > $warn)');
    }
  }

  for (final f in files) {
    switch (f.kind) {
      case FileKind.excluded:
        continue;
      case FileKind.test:
        check(f.path, f.lines, testWarn, testError, 'Testdatei');
      case FileKind.production:
        check(f.path, f.lines, prodWarn, prodError, 'Datei');
      case FileKind.testingLib:
        check(f.path, f.lines, prodWarn, null, 'Datei unter lib/testing');
    }
    if (f.kind == FileKind.test) continue;
    final hard = f.kind == FileKind.production;
    for (final fn in f.functions) {
      check(
        '${f.path}#${fn.name}',
        fn.lines,
        fnWarn,
        hard ? fnError : null,
        'Funktion',
      );
    }
    for (final c in f.classes) {
      check('${f.path}#${c.name}', c.lines, classWarn, null, 'Klasse');
    }
  }
  for (final key in allow.keys) {
    if (!seen.contains(key)) {
      r.errors.add(
        '$key: nicht mehr vorhanden: Eintrag aus tool/size_allowlist.yaml entfernen',
      );
    }
  }
  return r;
}

/// Messwerte für `--report`: größte Dateien, Klassen und Funktionen.
String renderReport(List<FileSize> files) {
  final b = StringBuffer();
  void top(String title, List<(int, String)> rows, int n) {
    rows.sort((a, z) => z.$1.compareTo(a.$1));
    b.writeln('\n## $title');
    for (final (lines, what) in rows.take(n)) {
      b.writeln('${'$lines'.padLeft(5)}  $what');
    }
  }

  final measured = files.where((f) => f.kind != FileKind.excluded).toList();
  final prod = measured.where((f) => f.kind != FileKind.test).toList();
  final tests = measured.where((f) => f.kind == FileKind.test).toList();
  final prodLines = prod.fold(0, (s, f) => s + f.lines);
  final testLines = tests.fold(0, (s, f) => s + f.lines);
  b.writeln(
    'Produktivcode: ${prod.length} Dateien, $prodLines Zeilen. '
    'Tests: ${tests.length} Dateien, $testLines Zeilen.',
  );
  top('Top 25 Dateien (Produktivcode inkl. lib/testing)', [
    for (final f in prod) (f.lines, f.path),
  ], 25);
  top('Top 10 Testdateien', [for (final f in tests) (f.lines, f.path)], 10);
  top('Top 15 Klassen', [
    for (final f in prod)
      for (final c in f.classes) (c.lines, '${f.path}:${c.line} ${c.name}'),
  ], 15);
  top('Top 25 Funktionen', [
    for (final f in prod)
      for (final fn in f.functions)
        (fn.lines, '${f.path}:${fn.line} ${fn.name}'),
  ], 25);
  return b.toString();
}
