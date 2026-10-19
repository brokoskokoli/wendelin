// Gate: Format, Analyse, Tests mit Abdeckung, Abhängigkeitsregeln,
// Secret-Scan, Größen, Pfade in der Doku, Selbsttests der Werkzeuge und
// Geräte-Skripte. Aufruf und Schalter: `dart run tool/gate.dart --help`.
import 'dart:io';

import 'src/gate_cache.dart';
import 'src/gate_changed.dart';
import 'src/gate_lock.dart';
import 'src/gate_run.dart';
import 'src/gate_rust.dart';
import 'src/kotlin_unit.dart';

/// Mindestabdeckung je Paket unter `packages/` (und `evals`).
const minCoverage = 85.0;

/// Mindestabdeckung von `app/lib/di/` (Verdrahtung der App, WP39). Die
/// Logik liegt in den Paketen und fällt unter [minCoverage]; hier zählt
/// nur, dass die Verdrahtung und die Adapter von Tests durchlaufen werden.
/// Gemessen nach WP39: 93,7 %; Schwelle = Messwert abgerundet auf volle
/// 5 %, mindestens 70 % (`docs/ENGINEERING.md`, Gate Schritt 4).
const minAppDiCoverage = 90.0;

const usage = '''
Gate: muss vor jedem Commit grün sein.

  dart run tool/gate.dart                  alles (Pakete, evals, App, Prüfungen)
  dart run tool/gate.dart --no-app         ohne Flutter-App (wie der Ubuntu-Job in CI)
  dart run tool/gate.dart wendelin_core    nur diese Pakete (+ globale Prüfungen, Selbsttests)
  dart run tool/gate.dart native/attest    nur das Rust-Crate (fmt, clippy, test, deny, frb aktuell)
  dart run tool/gate.dart --changed        nur geänderte Pakete und ihre Abhängigen
  dart run tool/gate.dart --only <paket>   nur dieses Ziel: ohne globale Prüfungen und Werkzeug-Selbsttests (CI-Matrix)
  dart run tool/gate.dart --globals        nur globale Prüfungen und Werkzeug-Selbsttests (eigener CI-Job)

Schalter:
  --changed       Prüft nur Pakete, die gegenüber dem Merge-Base mit
                  origin/main (bzw. main) oder im Arbeitsbaum geändert sind,
                  plus alle Pakete, die transitiv von ihnen abhängen. Format
                  und Analyse laufen nur auf diesen Ordnern. Nur Doku:
                  nur globale Prüfungen. Für schnelle Zwischenstände. Vor
                  Commit und Merge gilt das volle Gate (siehe CLAUDE.md).
  --base=<ref>    Vergleichsbasis für --changed (Standard: origin/main).
  --only          Die angegebenen Ziele allein: weder globale Prüfungen noch
                  Selbsttests der Werkzeuge (die laufen mit --globals einmal).
  --globals       Keine Pakete, nur globale Prüfungen und Selbsttests.
  --shard=<i>/<n> Mit --only: nur Shard i von n der Paket-Tests (1-basiert);
                  die Abdeckung schreibt der Lauf nach <paket>/coverage/lcov.info,
                  die Schwelle prüft tool/check_pkg_coverage.dart über alle Shards.
  --no-app        Ohne Flutter-App (Analyse und Tests der App entfallen).
  --no-cache      Ohne Gate-Cache: alle Schritte laufen. Der Cache (grüne
                  Schritte, Schlüssel = Inhalt der Dateien + Lockfiles +
                  Toolchain + tool/) ist auch aus mit WENDELIN_GATE_CACHE=0
                  und in CI (CI=true). Treffer stehen als „cached“.
  --verbose, -v   Bisherige Ausgabe: Unterprozesse schreiben direkt,
                  Standard-Reporter der Tests, Größen-Warnungen als Liste.
  --help, -h      Diese Hilfe.

Standard ist die kompakte Ausgabe: eine Zeile je Schritt, bei Fehlern die
letzten 200 Zeilen des Schritts, am Ende eine Tabelle mit Ergebnis und
Dauer und die Zeile GATE GRÜN bzw. GATE ROT: <Schritte>.''';

const _flags = {
  '--changed',
  '--only',
  '--globals',
  '--no-app',
  '--no-cache',
  '--verbose',
  '-v',
  '--help',
  '-h',
};

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(usage);
    return;
  }
  final unknown = args.where(
    (a) =>
        a.startsWith('-') &&
        !_flags.contains(a) &&
        !a.startsWith('--base=') &&
        !a.startsWith('--shard='),
  );
  if (unknown.isNotEmpty) {
    stderr.writeln('Unbekannter Schalter: ${unknown.join(' ')}\n\n$usage');
    exitCode = 64;
    return;
  }
  final total = Stopwatch()..start();
  final verbose = args.contains('--verbose') || args.contains('-v');
  final gate = Gate(
    verbose: verbose,
    cache: GateCache.fromEnvironment(Platform.environment, args),
  );
  final notes = <String>[];
  final scope = _scope(args, notes);
  if (scope == null) {
    exitCode = 2;
    return;
  }
  final shard = _shard(args);
  if (args.any((a) => a.startsWith('--shard=')) &&
      (shard == null || !args.contains('--only'))) {
    stderr.writeln(
      '--shard=<i>/<n> (1 <= i <= n) gilt nur zusammen mit --only.',
    );
    exitCode = 64;
    return;
  }
  for (final n in notes) {
    stdout.writeln(n);
  }
  // Rechnerweit höchstens 2 Läufe gleichzeitig (WP97); der Slot wird auch bei
  // Fehlern und bei SIGINT/SIGTERM freigegeben.
  await withGateSlot(gateSlotsFromEnvironment(Platform.environment), () async {
    final (:targets, :tooling, :kotlin, :globalChecks) = scope;
    bool wants(String t) => targets == null || targets.contains(t);
    final packages = {
      for (final MapEntry(:key, :value) in _packageDirs().entries)
        if (wants(key)) key: value,
    };
    final hasApp = File('app/pubspec.yaml').existsSync() && wants(appTarget);
    final deps = workspaceDeps();
    // Weitere Shards formatieren und analysieren nicht noch einmal.
    if (shard == null || shard.index == 1) {
      await _codeSteps(gate, packages, tooling: tooling, app: hasApp);
    }
    if (wants(rustTarget)) await _rustSteps(gate);
    for (final MapEntry(key: name, value: dir) in packages.entries) {
      await _testPackage(gate, name, dir, cacheRoots(name, deps), shard: shard);
    }
    if (hasApp && !args.contains('--no-app')) {
      await _appSteps(gate, cacheRoots(appTarget, deps));
    }
    if (kotlin && hasApp && !args.contains('--no-app')) {
      await _kotlinStep(gate);
    }
    if (globalChecks) await _globalSteps(gate, tooling: tooling);
    exitCode = gate.finish(total.elapsed, notes: notes);
  });
  if (_reports.existsSync()) _reports.deleteSync(recursive: true);
}

/// Rust-Crate `native/attest`; ohne Toolchain lokal übersprungen, in CI Pflicht.
Future<void> _rustSteps(Gate gate) async {
  final env = Platform.environment;
  final path = (env['PATH'] ?? '').split(':').where((d) => d.isNotEmpty);
  await rustSteps(
    gate,
    ci: env['CI'] == 'true',
    env: env,
    toolDir: (t) => findToolDir(
      t.binary,
      path: path,
      home: env['HOME'] ?? '',
      exists: (f) => File(f).existsSync(),
    ),
  );
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
    ], cacheSpec: CacheSpec(formatDirs));
  }
  if (dartDirs.isNotEmpty) {
    await gate.step('analyze', 'dart', [
      'analyze',
      '--fatal-infos',
      ...dartDirs,
    ], cacheSpec: analyzeSpec(dartDirs));
  }
}

/// Analyse und Tests der Flutter-App.
Future<void> _appSteps(Gate gate, List<String> roots) async {
  final spec = appSpec(roots);
  final appDirs = _appDirs();
  // Explizite Pfade: Ohne sie analysiert `flutter analyze` im Workspace
  // nichts, weil die Root-analysis_options `app/**` ausschließt.
  await gate.step(
    'analyze app',
    'flutter',
    ['analyze', '--fatal-infos', ...appDirs],
    cwd: 'app',
    cacheSpec: spec,
  );
  if (!appDirs.contains('test')) return;
  final json = _reportFile('app');
  clearCoverage('app');
  await gate.step(
    'test app',
    'flutter',
    ['test', '--coverage', ..._testFlags(gate.verbose, json)],
    cwd: 'app',
    report: json,
    cacheSpec: spec,
    check: (r) async {
      final tests = testDetail(countTests(json));
      if (r.exitCode != 0) return (detail: tests, failure: null);
      final lcov = File('app/coverage/lcov.info');
      if (!lcov.existsSync()) {
        return (detail: tests, failure: 'keine Abdeckung (app/coverage)');
      }
      final cov = lcovCoverage(lcov.readAsLinesSync(), under: 'lib/di/');
      final c = '${cov.toStringAsFixed(1)} %';
      return (
        detail: [if (tests.isNotEmpty) tests, 'di $c'].join(', '),
        failure: cov < minAppDiCoverage
            ? 'Abdeckung app/lib/di $c < $minAppDiCoverage %'
            : null,
      );
    },
  );
}

/// JVM-Unit-Tests der Kotlin-Logik. Ohne Android-SDK (oder ohne den von
/// Flutter erzeugten Gradle-Wrapper) steht der Schritt als übersprungen in
/// der Zusammenfassung, nicht als grün.
Future<void> _kotlinStep(Gate gate) async {
  const name = 'kotlin-unit';
  final sdk = androidSdk(
    Platform.environment,
    Platform.environment['HOME'] ?? '',
    (p) => Directory(p).existsSync(),
  );
  final skip = sdk == null
      ? 'kein Android-SDK'
      : !File('app/android/gradlew').existsSync()
      ? 'kein Gradle-Wrapper (flutter build apk erzeugt ihn)'
      : null;
  if (skip != null) {
    gate.record(StepResult(name, Outcome.skipped, Duration.zero, skip));
    return;
  }
  clearReports(kotlinReportDir);
  // Zu neues JDK (JAVA_HOME oder PATH): Gradle bricht, also openjdk@21 bzw. JBR.
  final jdk = jdkVersion(Platform.environment);
  final home = gradleJavaHome(jdk, (h) => File('$h/bin/java').existsSync());
  await gate.step(
    name,
    home == null ? 'bash' : 'env',
    [
      if (home != null) 'JAVA_HOME=$home',
      'bash',
      'gradlew',
      ':app:testDebugUnitTest',
      '-q',
    ],
    cwd: 'app/android',
    cacheSpec: kotlinSpec(
      sdk ?? '',
      jdk: '$jdk${home == null ? '' : ' -> $home'}',
    ),
    check: (_) async {
      final c = countJUnit(readReports(kotlinReportDir));
      return (
        detail: '${c.tests} Tests',
        failure: c.tests == 0 ? 'keine Testberichte gefunden' : null,
      );
    },
  );
}

/// Prüfungen über das ganze Repo und Selbsttests der Werkzeuge.
Future<void> _globalSteps(Gate gate, {required bool tooling}) async {
  const all = CacheSpec(['.']);
  await gate.step('check_deps', 'dart', [
    'run',
    'tool/check_deps.dart',
  ], cacheSpec: all);
  await gate.step('check_secrets', 'dart', [
    'run',
    'tool/check_secrets.dart',
  ], cacheSpec: all);
  await gate.step(
    'check_sizes',
    'dart',
    ['run', 'tool/check_sizes.dart', if (gate.verbose) '--verbose'],
    cacheSpec: all,
    check: (r) async => (
      detail: RegExp(r'\d+ Warnungen').stringMatch(r.lines.join('\n')) ?? '',
      failure: null,
    ),
  );
  await gate.step('check_ignores', 'dart', [
    'run',
    'tool/check_ignores.dart',
  ], cacheSpec: all);
  await gate.step('check_flaky', 'dart', [
    'run',
    'tool/check_flaky.dart',
  ], cacheSpec: all);
  await gate.step('check_texts', 'dart', [
    'run',
    'tool/check_texts.dart',
  ], cacheSpec: all);
  await gate.step('check_manifest', 'bash', [
    'tool/check_apk.sh',
    '--manifest',
  ], cacheSpec: all);
  await gate.step('check_docs', 'dart', [
    'run',
    'tool/check_docs.dart',
  ], cacheSpec: all);
  await gate.step('l10n aktuell', 'dart', [
    'run',
    'tool/l10n_merge.dart',
    '--check',
  ], cacheSpec: all);
  await gate.step('check_registry', 'dart', [
    'run',
    'tool/check_registry.dart',
  ], cacheSpec: all);
  await gate.step('check_channels', 'dart', [
    'run',
    'tool/check_channels.dart',
  ], cacheSpec: all);
  if (!tooling) return;
  // Selbsttests der Werkzeuge (gate, check_sizes, check_docs) und der
  // Geräte-Skripte (nur bash, kein Android-SDK nötig).
  await gate.step('tool self-test', 'dart', [
    'run',
    'tool/self_test.dart',
  ], cacheSpec: all);
  await gate.step('android_device self-test', 'bash', [
    'tool/android_device.sh',
    '--self-test',
  ], cacheSpec: const CacheSpec(['tool'], tools: []));
  await gate.step('check_apk self-test', 'bash', [
    'tool/check_apk.sh',
    '--self-test',
  ], cacheSpec: const CacheSpec(['tool'], tools: []));
}

/// Prüfumfang: `targets == null` heißt alle Pakete. `null` bei einem
/// Git-Fehler im Modus `--changed`.
({Set<String>? targets, bool tooling, bool kotlin, bool globalChecks})? _scope(
  List<String> args,
  List<String> notes,
) {
  if (!args.contains('--changed')) return explicitScope(args);
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
    return (targets: null, tooling: true, kotlin: true, globalChecks: true);
  }
  notes.add(
    sel.targets.isEmpty
        ? '$head, kein Paket betroffen: nur globale Prüfungen'
        : '$head. Geprüft: '
              '${sel.targets.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
  );
  // Kotlin-Unit-Tests nur, wenn sich unter app/android etwas geändert hat.
  return (
    targets: sel.targets.keys.toSet(),
    tooling: sel.tooling,
    kotlin: changed.any((p) => p.startsWith('app/android/')),
    globalChecks: true,
  );
}

/// `--shard=i/n` (1-basiert); `null` ohne gültige Angabe.
({int index, int total})? _shard(List<String> args) {
  final a = args.where((a) => a.startsWith('--shard=')).firstOrNull;
  final m = RegExp(r'^--shard=(\d+)/(\d+)$').firstMatch(a ?? '');
  if (m == null) return null;
  final i = int.parse(m[1]!), n = int.parse(m[2]!);
  return i >= 1 && i <= n ? (index: i, total: n) : null;
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

Future<void> _testPackage(
  Gate gate,
  String name,
  String dir,
  List<String> roots, {
  ({int index, int total})? shard,
}) async {
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
    shard == null ? 'test $name' : 'test $name ${shard.index}/${shard.total}',
    'dart',
    [
      'test',
      '--coverage=coverage',
      ...shardFlags(shard),
      ..._testFlags(gate.verbose, json),
    ],
    cwd: dir,
    report: json,
    cacheSpec: CacheSpec(roots),
    check: (r) async {
      final tests = testDetail(countTests(json));
      if (r.exitCode != 0) return (detail: tests, failure: null);
      final cov = await _coverage(dir);
      // Geteilte Läufe prüfen die Schwelle erst über alle Shards.
      if (shard != null) {
        return (
          detail: '$tests, Shard ${shard.index}/${shard.total}',
          failure: null,
        );
      }
      return coverageCheck(cov, tests, minCoverage);
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
