// Gate: Format, Analyse, Tests mit Abdeckung, Abhängigkeitsregeln,
// Secret-Scan, Größen, Pfade in der Doku, Selbsttests der Werkzeuge und
// Geräte-Skripte. Aufruf und Schalter: `dart run tool/gate.dart --help`.
import 'dart:io';

import 'src/gate_changed.dart';
import 'src/gate_run.dart';

/// Mindestabdeckung je Paket unter `packages/` (und `evals`).
const minCoverage = 85.0;

const usage = '''
Gate: muss vor jedem Commit grün sein.

  dart run tool/gate.dart                  alles (Pakete, evals, App, Prüfungen)
  dart run tool/gate.dart --no-app         ohne Flutter-App (wie der Ubuntu-Job in CI)
  dart run tool/gate.dart wendelin_core    nur diese Pakete (+ globale Prüfungen, Selbsttests)
  dart run tool/gate.dart --changed        nur geänderte Pakete und ihre Abhängigen

Schalter:
  --changed       Prüft nur Pakete, die gegenüber dem Merge-Base mit
                  origin/main (bzw. main) oder im Arbeitsbaum geändert sind,
                  plus alle Pakete, die transitiv von ihnen abhängen. Format
                  und Analyse laufen nur auf diesen Ordnern. Nur Doku:
                  nur globale Prüfungen. Für schnelle Zwischenstände. Vor
                  Commit und Merge gilt das volle Gate (siehe CLAUDE.md).
  --base=<ref>    Vergleichsbasis für --changed (Standard: origin/main).
  --no-app        Ohne Flutter-App (Analyse und Tests der App entfallen).
  --verbose, -v   Bisherige Ausgabe: Unterprozesse schreiben direkt,
                  Standard-Reporter der Tests, Größen-Warnungen als Liste.
  --help, -h      Diese Hilfe.

Standard ist die kompakte Ausgabe: eine Zeile je Schritt, bei Fehlern die
letzten 200 Zeilen des Schritts, am Ende eine Tabelle mit Ergebnis und
Dauer und die Zeile GATE GRÜN bzw. GATE ROT: <Schritte>.''';

const _flags = {'--changed', '--no-app', '--verbose', '-v', '--help', '-h'};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return;
  }
  final unknown = args.where(
    (a) => a.startsWith('-') && !_flags.contains(a) && !a.startsWith('--base='),
  );
  if (unknown.isNotEmpty) {
    stderr.writeln('Unbekannter Schalter: ${unknown.join(' ')}\n\n$usage');
    exitCode = 64;
    return;
  }
  final total = Stopwatch()..start();
  final verbose = args.contains('--verbose') || args.contains('-v');
  final gate = Gate(verbose: verbose);
  final notes = <String>[];
  final scope = _scope(args, notes);
  if (scope == null) {
    exitCode = 2;
    return;
  }
  for (final n in notes) {
    stdout.writeln(n);
  }
  final (:targets, :tooling) = scope;
  bool wants(String t) => targets == null || targets.contains(t);
  final packages = {
    for (final MapEntry(:key, :value) in _packageDirs().entries)
      if (wants(key)) key: value,
  };
  final hasApp = File('app/pubspec.yaml').existsSync() && wants(appTarget);
  await _codeSteps(gate, packages, tooling: tooling, app: hasApp);
  for (final MapEntry(key: name, value: dir) in packages.entries) {
    await _testPackage(gate, name, dir);
  }
  if (hasApp && !args.contains('--no-app')) await _appSteps(gate);
  await _globalSteps(gate, tooling: tooling);
  exitCode = gate.finish(total.elapsed, notes: notes);
  _reports.deleteSync(recursive: true);
}

/// Ordner der App, die Format, Analyse und Tests betreffen.
List<String> _appDirs() => [
  for (final d in ['lib', 'test', 'integration_test'])
    if (Directory('app/$d').existsSync()) d,
];

/// Format und Analyse, beschränkt auf die geprüften Ordner.
Future<void> _codeSteps(
  Gate gate,
  Map<String, String> packages, {
  required bool tooling,
  required bool app,
}) async {
  final dartDirs = [...packages.values, if (tooling) 'tool'];
  final formatDirs = [...dartDirs, if (app) ..._appDirs().map((d) => 'app/$d')];
  if (formatDirs.isNotEmpty) {
    await gate.step('format', 'dart', [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      ...formatDirs,
    ]);
  }
  if (dartDirs.isNotEmpty) {
    await gate.step('analyze', 'dart', [
      'analyze',
      '--fatal-infos',
      ...dartDirs,
    ]);
  }
}

/// Analyse und Tests der Flutter-App.
Future<void> _appSteps(Gate gate) async {
  final appDirs = _appDirs();
  // Explizite Pfade: Ohne sie analysiert `flutter analyze` im Workspace
  // nichts, weil die Root-analysis_options `app/**` ausschließt.
  await gate.step('analyze app', 'flutter', [
    'analyze',
    '--fatal-infos',
    ...appDirs,
  ], cwd: 'app');
  if (!appDirs.contains('test')) return;
  final json = _reportFile('app');
  await gate.step(
    'test app',
    'flutter',
    ['test', ..._testFlags(gate.verbose, json)],
    cwd: 'app',
    check: (_) async => (detail: testDetail(countTests(json)), failure: null),
  );
}

/// Prüfungen über das ganze Repo und Selbsttests der Werkzeuge.
Future<void> _globalSteps(Gate gate, {required bool tooling}) async {
  await gate.step('check_deps', 'dart', ['run', 'tool/check_deps.dart']);
  await gate.step('check_secrets', 'dart', ['run', 'tool/check_secrets.dart']);
  await gate.step(
    'check_sizes',
    'dart',
    ['run', 'tool/check_sizes.dart', if (gate.verbose) '--verbose'],
    check: (r) async => (
      detail: RegExp(r'\d+ Warnungen').stringMatch(r.lines.join('\n')) ?? '',
      failure: null,
    ),
  );
  await gate.step('check_docs', 'dart', ['run', 'tool/check_docs.dart']);
  await gate.step('check_channels', 'dart', [
    'run',
    'tool/check_channels.dart',
  ]);
  if (!tooling) return;
  // Selbsttests der Werkzeuge (gate, check_sizes, check_docs) und der
  // Geräte-Skripte (nur bash, kein Android-SDK nötig).
  await gate.step('tool self-test', 'dart', ['run', 'tool/self_test.dart']);
  await gate.step('android_device self-test', 'bash', [
    'tool/android_device.sh',
    '--self-test',
  ]);
  await gate.step('check_apk self-test', 'bash', [
    'tool/check_apk.sh',
    '--self-test',
  ]);
}

/// Prüfumfang: `targets == null` heißt alle Pakete. `null` bei einem
/// Git-Fehler im Modus `--changed`.
({Set<String>? targets, bool tooling})? _scope(
  List<String> args,
  List<String> notes,
) {
  final only = args.where((a) => !a.startsWith('-')).toSet();
  if (!args.contains('--changed')) {
    return only.isEmpty
        ? (targets: null, tooling: true)
        // Mit Paketen laufen die Werkzeug- und Geräte-Selbsttests weiter mit.
        : (targets: only, tooling: true);
  }
  final baseArg = args.where((a) => a.startsWith('--base=')).firstOrNull;
  final base = baseArg?.substring(7) ?? _defaultBase();
  final List<String> changed;
  try {
    changed = changedPaths(base, _git);
  } on ProcessException catch (e) {
    stderr.writeln('--changed: ${e.message}');
    return null;
  }
  final sel = selectChanged(changed, workspaceDeps());
  final head = '--changed gegen $base: ${changed.length} geänderte Dateien';
  if (sel.fullReason case final why?) {
    notes.add('$head, volles Gate ($why)');
    return (targets: null, tooling: true);
  }
  notes.add(
    sel.targets.isEmpty
        ? '$head, kein Paket betroffen: nur globale Prüfungen'
        : '$head. Geprüft: '
              '${sel.targets.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
  );
  return (targets: sel.targets.keys.toSet(), tooling: sel.tooling);
}

String _defaultBase() =>
    Process.runSync('git', [
          'rev-parse',
          '--verify',
          '--quiet',
          'origin/main',
        ]).exitCode ==
        0
    ? 'origin/main'
    : 'main';

String _git(List<String> a) {
  final r = Process.runSync('git', a);
  if (r.exitCode != 0) {
    throw ProcessException('git', a, '${r.stderr}'.trim(), r.exitCode);
  }
  return r.stdout as String;
}

/// Prüfziel → Ordner, sortiert, `evals` am Ende.
Map<String, String> _packageDirs() {
  final dirs = Directory(
    'packages',
  ).listSync().whereType<Directory>().map((d) => d.path).toList()..sort();
  return {
    for (final d in dirs) d.split('/').last: d,
    if (Directory('evals/lib').existsSync() &&
        File('evals/pubspec.yaml').existsSync())
      evalsTarget: 'evals',
  };
}

List<String> _testFlags(bool verbose, String json) => [
  if (!verbose) '--reporter=failures-only',
  '--file-reporter=json:$json',
];

/// Ordner für die JSON-Berichte der Testläufe, am Ende gelöscht.
final _reports = Directory.systemTemp.createTempSync('wendelin_gate_');

String _reportFile(String name) => '${_reports.path}/$name.json';

Future<void> _testPackage(Gate gate, String name, String dir) async {
  // Noch leeres Paket (nur Gerüst, kein Code unter lib/src): überspringen.
  final src = Directory('$dir/lib/src');
  final hasCode =
      src.existsSync() &&
      src.listSync(recursive: true).any((f) => f.path.endsWith('.dart'));
  if (!hasCode) {
    gate.record(
      StepResult('test $name', Outcome.skipped, Duration.zero, 'kein Code'),
    );
    return;
  }
  final test = Directory('$dir/test');
  if (!test.existsSync() ||
      !test
          .listSync(recursive: true)
          .any((f) => f.path.endsWith('_test.dart'))) {
    gate.record(
      StepResult('test $name', Outcome.red, Duration.zero, 'keine Tests'),
    );
    return;
  }
  final json = _reportFile(name);
  clearCoverage(dir);
  await gate.step(
    'test $name',
    'dart',
    ['test', '--coverage=coverage', ..._testFlags(gate.verbose, json)],
    cwd: dir,
    check: (r) async {
      final tests = testDetail(countTests(json));
      if (r.exitCode != 0) return (detail: tests, failure: null);
      return coverageCheck(await _coverage(dir), tests, minCoverage);
    },
  );
}

/// Zeilenabdeckung aus dem von `dart test --coverage` geschriebenen JSON,
/// nur für Dateien unter lib/ (ohne generierte *.g.dart/*.steps.dart und
/// lib/testing/).
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
  return lcovCoverage(File(lcov).readAsLinesSync());
}
