// Fasst lcov-Dateien der Shards eines Pakets zusammen und prüft die Abdeckung
// gegen die Schwelle des Gates (CI, WP110: wendelin_integrations in 2 Shards).
//
// Aufruf: dart run tool/check_pkg_coverage.dart <paket> <lcov.info>...
import 'dart:io';

import 'check_app_coverage.dart' show mergeLcov;
import 'gate.dart' show minCoverage;
import 'src/gate_run.dart' show lcovCoverage;

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Aufruf: check_pkg_coverage.dart <paket> <lcov.info>...');
    exitCode = 2;
    return;
  }
  final merged = mergeLcov([
    for (final f in args.skip(1)) File(f).readAsLinesSync(),
  ]);
  if (!merged.any((l) => l.startsWith('SF:'))) {
    stderr.writeln('Keine Dateien in den lcov-Berichten (leere Shards?).');
    exitCode = 1;
    return;
  }
  final cov = lcovCoverage(merged);
  stdout.writeln(
    '${args.first}: ${cov.toStringAsFixed(1)} % über ${args.length - 1} Shards '
    '(min $minCoverage %)',
  );
  if (cov < minCoverage) exitCode = 1;
}
