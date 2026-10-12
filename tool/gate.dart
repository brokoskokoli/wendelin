// Gate: format, analyze, tests mit Abdeckung, Abhängigkeitsregeln, Secret-Scan.
//
//   dart run tool/gate.dart                  # alles
//   dart run tool/gate.dart wendelin_core    # nur ein Paket (+ globale Prüfungen)
//   dart run tool/gate.dart --no-app         # ohne Flutter-App
import 'dart:io';

const minCoverage = 85.0;

Future<void> main(List<String> args) async {
  final only = args.where((a) => !a.startsWith('--')).toSet();
  final skipApp = args.contains('--no-app');
  final failures = <String>[];

  Future<bool> step(
    String name,
    String exe,
    List<String> a, {
    String? cwd,
  }) async {
    stdout.writeln('\n== $name');
    final p = await Process.start(
      exe,
      a,
      workingDirectory: cwd,
      mode: ProcessStartMode.inheritStdio,
    );
    final ok = await p.exitCode == 0;
    if (!ok) failures.add(name);
    return ok;
  }

  await step('format', 'dart', [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    'packages',
    'tool',
    'evals',
    if (Directory('app/lib').existsSync()) 'app/lib',
    if (Directory('app/test').existsSync()) 'app/test',
  ]);
  await step('analyze', 'dart', [
    'analyze',
    '--fatal-infos',
    'packages',
    'tool',
    'evals',
  ]);

  final packages = Directory(
    'packages',
  ).listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
  if (Directory('evals/lib').existsSync() &&
      File('evals/pubspec.yaml').existsSync()) {
    packages.add('evals');
  }
  for (final dir in packages) {
    final name = dir.split('/').last;
    if (only.isNotEmpty && !only.contains(name)) continue;
    if (!Directory('$dir/test').existsSync() ||
        Directory('$dir/test')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('_test.dart'))
            .isEmpty) {
      stdout.writeln('\n== test $name: keine Tests');
      failures.add('test $name (keine Tests)');
      continue;
    }
    final ok = await step('test $name', 'dart', [
      'test',
      '--coverage=coverage',
    ], cwd: dir);
    if (!ok) continue;
    final cov = await _coverage(dir);
    stdout.writeln('Abdeckung $name: ${cov.toStringAsFixed(1)} %');
    if (cov < minCoverage) {
      failures.add(
        'coverage $name ${cov.toStringAsFixed(1)} % < $minCoverage %',
      );
    }
  }

  if (!skipApp &&
      File('app/pubspec.yaml').existsSync() &&
      (only.isEmpty || only.contains('app'))) {
    await step('analyze app', 'flutter', [
      'analyze',
      '--fatal-infos',
    ], cwd: 'app');
    await step('test app', 'flutter', ['test'], cwd: 'app');
  }

  await step('check_deps', 'dart', ['run', 'tool/check_deps.dart']);
  await step('check_secrets', 'dart', ['run', 'tool/check_secrets.dart']);

  stdout.writeln('\n==========');
  if (failures.isEmpty) {
    stdout.writeln('GATE GRÜN');
  } else {
    stdout.writeln('GATE ROT:\n- ${failures.join('\n- ')}');
    exitCode = 1;
  }
}

/// Zeilenabdeckung aus dem von `dart test --coverage` geschriebenen JSON,
/// nur für Dateien unter lib/ (ohne generierte *.g.dart und lib/testing/).
Future<double> _coverage(String dir) async {
  final lcov = '$dir/coverage/lcov.info';
  final r = await Process.run('dart', [
    'run',
    'coverage:format_coverage',
    '--lcov',
    '--in=coverage',
    '--out=coverage/lcov.info',
    '--report-on=lib',
    '--check-ignore',
  ], workingDirectory: dir);
  if (r.exitCode != 0 || !File(lcov).existsSync()) {
    stderr.writeln(r.stderr);
    return 0;
  }
  var found = 0, hit = 0;
  var skip = false;
  for (final line in File(lcov).readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final f = line.substring(3);
      skip =
          f.endsWith('.g.dart') ||
          f.contains('/lib/testing/') ||
          f.endsWith('/lib/testing.dart');
    } else if (!skip && line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    } else if (!skip && line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    }
  }
  return found == 0 ? 100 : hit * 100 / found;
}
