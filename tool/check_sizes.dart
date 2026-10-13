// Größen-Check (docs/ENGINEERING.md, „Größen“): Datei-, Funktions- und
// Klassenlängen in Dart und Kotlin gegen die Schwellen, Bestandsdateien
// über der Fehlerschwelle gegen `tool/size_allowlist.yaml`.
//
//   dart run tool/check_sizes.dart            Fehler und Anzahl der Warnungen
//   dart run tool/check_sizes.dart --verbose  dazu alle Warnungen
//   dart run tool/check_sizes.dart --report   größte Dateien, Klassen, Funktionen
import 'dart:io';

import 'src/size_rules.dart';
import 'src/size_scan.dart';

const allowlistPath = 'tool/size_allowlist.yaml';
const _roots = ['packages', 'app', 'evals', 'tool'];
const _skipDirs = {'build', '.dart_tool', '.gradle', 'Pods', '.git', 'ios'};

void main(List<String> args) {
  final sw = Stopwatch()..start();
  final files = scanRepo();
  if (args.contains('--report')) {
    stdout.write(renderReport(files));
    return;
  }
  final errors = <String>[];
  final allowFile = File(allowlistPath);
  final allow = allowFile.existsSync()
      ? parseAllowlist(allowFile.readAsStringSync(), errors)
      : <String, AllowEntry>{};
  final r = evaluate(files, allow);
  errors.addAll(r.errors);
  errors.forEach(stderr.writeln);
  if (args.contains('--verbose')) r.warnings.forEach(stdout.writeln);
  final summary =
      '${errors.length} Fehler, ${r.warnings.length} Warnungen '
      '(${files.length} Dateien, ${sw.elapsedMilliseconds} ms)';
  if (errors.isEmpty) {
    stdout.writeln('check_sizes: ok, $summary');
  } else {
    stderr.writeln('check_sizes: ROT, $summary');
    exitCode = 1;
  }
}

/// Misst alle Dart- und Kotlin-Dateien unter den Code-Ordnern.
List<FileSize> scanRepo() {
  final result = <FileSize>[];
  void walk(Directory dir) {
    for (final e in dir.listSync()) {
      final name = e.path.split('/').last;
      if (e is Directory) {
        if (!_skipDirs.contains(name)) walk(e);
      } else if (e is File &&
          (name.endsWith('.dart') || name.endsWith('.kt'))) {
        result.add(measureFile(e.path, e.readAsStringSync()));
      }
    }
  }

  for (final r in _roots) {
    final d = Directory(r);
    if (d.existsSync()) walk(d);
  }
  result.sort((a, b) => a.path.compareTo(b.path));
  return result;
}

/// Misst eine Datei; Funktionen und Klassen nur außerhalb von Tests.
FileSize measureFile(String path, String text) {
  final lines = text.isEmpty
      ? 0
      : '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
  final kind = kindOf(path);
  if (kind == FileKind.test || kind == FileKind.excluded) {
    return FileSize(path, lines);
  }
  final s = measure(text, kotlin: path.endsWith('.kt'));
  return FileSize(path, lines, functions: s.functions, classes: s.classes);
}
