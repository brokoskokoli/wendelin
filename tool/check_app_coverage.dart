// Fasst lcov-Dateien der App-Test-Shards zusammen und prüft die Abdeckung
// von app/lib/di gegen die Schwelle des Gates (CI, WP95).
//
// Aufruf: dart run tool/check_app_coverage.dart <lcov.info>...
import 'dart:io';

import 'gate.dart' show minAppDiCoverage;
import 'src/gate_run.dart' show lcovCoverage;

/// Vereinigt die Treffer je Datei und Zeile über mehrere lcov-Berichte.
List<String> mergeLcov(Iterable<Iterable<String>> reports) {
  final hits = <String, Map<int, int>>{};
  for (final lines in reports) {
    Map<int, int>? file;
    for (final line in lines) {
      if (line.startsWith('SF:')) {
        file = hits.putIfAbsent(line.substring(3), () => {});
      } else if (file != null && line.startsWith('DA:')) {
        final p = line.substring(3).split(',');
        final n = int.parse(p[0]);
        file[n] = (file[n] ?? 0) + int.parse(p[1]);
      }
    }
  }
  return [
    for (final MapEntry(:key, :value) in hits.entries) ...[
      'SF:$key',
      'LF:${value.length}',
      'LH:${value.values.where((h) => h > 0).length}',
      'end_of_record',
    ],
  ];
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Aufruf: check_app_coverage.dart <lcov.info>...');
    exitCode = 2;
    return;
  }
  final merged = mergeLcov([for (final f in args) File(f).readAsLinesSync()]);
  final cov = lcovCoverage(merged, under: 'lib/di/');
  stdout.writeln(
    'app/lib/di: ${cov.toStringAsFixed(1)} % (min $minAppDiCoverage %)',
  );
  if (cov < minAppDiCoverage) exitCode = 1;
}
