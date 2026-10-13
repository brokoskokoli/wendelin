// Selbsttests der Werkzeuge unter tool/ (Gate, Größen-Check, Doku-Pfade).
// Läuft im Gate als Schritt „tool self-test“:
//
//   dart run tool/self_test.dart
import 'dart:io';

import 'src/doc_paths.dart';
import 'src/gate_changed.dart';
import 'src/gate_run.dart';
import 'src/self_check.dart';
import 'src/size_rules.dart';
import 'src/size_scan.dart';

Future<void> main() async {
  final t = SelfCheck();
  _changedSelection(t);
  await _gateRun(t);
  _sizeScan(t);
  _sizeRules(t);
  _docPaths(t);
  exitCode = t.finish('tool self-test');
}

void _changedSelection(SelfCheck t) {
  t.group('--changed Paketauswahl');
  final deps = workspaceDeps();
  const all = {
    'wendelin_core',
    'wendelin_providers',
    'wendelin_tools',
    'wendelin_agent',
    'wendelin_storage',
    'wendelin_integrations',
    'wendelin_voice',
    'wendelin_mcp',
    'evals',
    'app',
  };
  final cases = <String, (List<String>, Set<String>?)>{
    'core → alle Pakete und App': (
      ['packages/wendelin_core/lib/src/messages/message.dart'],
      all,
    ),
    'agent → agent, voice, evals, App': (
      ['packages/wendelin_agent/lib/src/agent_runner.dart'],
      {'wendelin_agent', 'wendelin_voice', 'evals', 'app'},
    ),
    'integrations → mcp, evals, App': (
      ['packages/wendelin_integrations/test/x_test.dart'],
      {'wendelin_integrations', 'wendelin_mcp', 'evals', 'app'},
    ),
    'nur docs → nur globale Prüfungen': (
      ['docs/ARCHITECTURE.md', 'README.md', 'packages/wendelin_core/README.md'],
      <String>{},
    ),
    'nur App': (['app/lib/main.dart'], {'app'}),
    'evals': (['evals/lib/src/cli.dart'], {'evals'}),
    'tool/gate.dart → alles': (['docs/x.md', 'tool/gate.dart'], null),
    'pubspec.lock → alles': (['pubspec.lock'], null),
    'analysis_options.yaml → alles': (['analysis_options.yaml'], null),
    'unbekanntes Paket → alles': (['packages/wendelin_neu/lib/a.dart'], null),
    'Fixture-Markdown zählt als Code': (
      ['packages/wendelin_integrations/test/fixtures/list.md'],
      {'wendelin_integrations', 'wendelin_mcp', 'evals', 'app'},
    ),
  };
  for (final MapEntry(key: name, value: (paths, want)) in cases.entries) {
    final s = selectChanged(paths, deps);
    if (want == null) {
      t.isTrue(s.fullReason != null, '$name: volles Gate');
    } else {
      t.isTrue(s.fullReason == null, '$name: kein volles Gate');
      t.eq(s.targets.keys.toSet(), want, name);
    }
  }
  final agent = selectChanged([
    'packages/wendelin_agent/lib/a.dart',
  ], deps).targets;
  t.eq(agent['wendelin_agent'], 'geändert', 'Grund geändertes Paket');
  t.eq(
    agent['wendelin_voice'],
    'hängt von wendelin_agent ab',
    'Grund abhängiges Paket',
  );
  final docs = selectChanged(['docs/a.md'], deps);
  t.isTrue(docs.globalOnly, 'nur Doku: globalOnly');
  final tool = selectChanged(['tool/check_sizes.dart'], deps);
  t.isTrue(tool.tooling && tool.targets.isEmpty, 'tool/: nur Werkzeuge');
}

Future<void> _gateRun(SelfCheck t) async {
  t.group('Gate-Ausführung');
  final out = StringBuffer();
  final gate = Gate(
    verbose: false,
    out: out,
    tailLines: 3,
    runner: (exe, args, {cwd, required verbose}) async => args.contains('rot')
        ? const ProcResult(1, ['a', 'b', 'test/x_test.dart: Fehler', 'd', 'e'])
        : ProcResult(0, ['Ausgabe ${args.join()}']),
  );
  t.isTrue(await gate.step('format', 'dart', ['ok']), 'grüner Schritt');
  t.isTrue(!await gate.step('test x', 'dart', ['rot']), 'roter Schritt');
  t.isTrue(
    !await gate.step('test y', 'dart', [
      'cov',
    ], check: (_) async => (detail: '80.0 %', failure: 'Abdeckung zu klein')),
    'Prüfung macht grünen Prozess rot',
  );
  final code = gate.finish(const Duration(seconds: 3));
  final text = out.toString();
  t.eq(code, 1, 'Exit-Code bei Rot');
  t.isTrue(
    !text.contains('Ausgabe ok'),
    'Ausgabe grüner Schritte bleibt gepuffert',
  );
  t.isTrue(
    text.contains('Ausgabe cov') && text.contains('Abdeckung zu klein'),
    'roter Prüfschritt zeigt Ausgabe und Grund',
  );
  t.isTrue(
    text.contains('test/x_test.dart: Fehler') && text.contains('  | e'),
    'Ende der Ausgabe des roten Schritts erscheint',
  );
  t.isTrue(
    text.contains('2 von 5 Zeilen ausgelassen'),
    'Kürzung mit Gesamtlänge',
  );
  t.isTrue(text.contains('GATE ROT: test x, test y'), 'Zeile GATE ROT');
  t.isTrue(text.contains('Gesamtdauer: 3.0 s'), 'Gesamtdauer');

  final green = Gate(
    verbose: false,
    out: StringBuffer(),
    runner: (exe, args, {cwd, required verbose}) async => const ProcResult(0),
  );
  await green.step('format', 'dart', []);
  green.record(
    const StepResult('test z', Outcome.skipped, Duration.zero, 'kein Code'),
  );
  t.eq(green.finish(Duration.zero), 0, 'Exit-Code bei Grün');
  final summary = renderSummary([
    const StepResult('test a', Outcome.ok, Duration(milliseconds: 1250), 'x'),
  ], const Duration(seconds: 2));
  t.isTrue(summary.contains('test a   ok              1.3 s  x'), summary);
  t.isTrue(summary.endsWith('GATE GRÜN'), 'GATE GRÜN am Ende');

  final dir = Directory.systemTemp.createTempSync('gate_selftest_');
  final json = File('${dir.path}/r.json')
    ..writeAsStringSync(
      [
        '{"type":"testDone","result":"success","hidden":false,"skipped":false}',
        '{"type":"testDone","result":"success","hidden":true,"skipped":false}',
        '{"type":"testDone","result":"failure","hidden":false,"skipped":false}',
        '{"type":"testDone","result":"success","hidden":false,"skipped":true}',
        '{"type":"done","success":false}',
      ].join('\n'),
    );
  t.eq(
    testDetail(countTests(json.path)),
    '2 Tests, 1 rot, 1 übersprungen',
    'Testanzahl aus JSON',
  );
  t.eq(countTests('${dir.path}/fehlt.json'), null, 'fehlender Bericht');
  dir.deleteSync(recursive: true);
}

void _sizeScan(SelfCheck t) {
  t.group('Klammer-Heuristik');
  const dart = r'''
// { Kommentar mit Klammer
class A extends B {
  final s = '${x.map((e) { return e; })} }';
  /* { */ void f({int a = 1}) {
    if (a > 0) {
      g(() {});
    }
  }

  @override
  int get n => switch (s) {
    _ => 1,
  };

  Future<void> h<T>(List<T> xs) async {
    final r = r'\'; final q = """ { """;
  }
}

String top(String a) => a;
''';
  final s = measure(dart);
  t.eq(s.classes.map((c) => '$c').toList(), ['A@2:17'], 'Klasse');
  t.eq(s.functions.map((f) => '$f').toList(), [
    'A.f@4:5',
    'A.n@11:3',
    'A.h@15:3',
    'top@20:1',
  ], 'Funktionen mit Zeile und Länge');
  const kotlin = r'''
class Channel(private val ctx: Context) : Handler {
    fun handle(call: Call) {
        val s = "${call.method} {"
        when (call.method) {
            "a" -> { }
        }
    }
    companion object {
        const val CHANNEL = "x/{"
    }
}
''';
  final k = measure(kotlin, kotlin: true);
  t.eq(k.classes.map((c) => '$c').toList(), [
    'object@8:3',
    'Channel@1:11',
  ], 'Kotlin-Klassen');
  t.eq(k.functions.map((f) => '$f').toList(), [
    'Channel.handle@2:6',
  ], 'Kotlin-Funktion');
}

void _sizeRules(SelfCheck t) {
  t.group('Größenregeln und Allowlist');
  t.eq(kindOf('packages/a/lib/src/x.dart'), FileKind.production, 'lib');
  t.eq(kindOf('packages/a/lib/testing/f.dart'), FileKind.testingLib, 'testing');
  t.eq(kindOf('app/test/x_test.dart'), FileKind.test, 'test');
  t.eq(kindOf('packages/a/lib/src/db.g.dart'), FileKind.excluded, '.g.dart');
  t.eq(
    kindOf('packages/s/test/drift/generated/v1.dart'),
    FileKind.excluded,
    'gen',
  );
  t.eq(kindOf('packages/a/test/fixtures/a.dart'), FileKind.excluded, 'fixture');
  t.eq(
    kindOf('app/android/app/src/androidTest/kotlin/T.kt'),
    FileKind.test,
    'androidTest',
  );

  final errors = <String>[];
  final allow = parseAllowlist('''
# Kommentar
lib/big.dart: 900  # WP37
lib/shrunk.dart: 900  # WP38
lib/gone.dart: 850  # WP39
lib/grown.dart: 820  # WP40
lib/noref.dart: 900
''', errors);
  t.eq(errors.length, 1, 'fehlender WP-Verweis ist ein Fehler');
  t.eq(allow['lib/big.dart']?.limit, 900, 'Grenze gelesen');

  String errorFor(List<FileSize> files, String key) =>
      evaluate(files, {key: allow[key]!}).errors.join('\n');
  t.eq(
    errorFor([const FileSize('lib/big.dart', 900)], 'lib/big.dart'),
    '',
    'an der Grenze ok',
  );
  t.isTrue(
    errorFor([
      const FileSize('lib/grown.dart', 821),
    ], 'lib/grown.dart').contains('gewachsen'),
    'Wachsen über die Grenze ist ein Fehler',
  );
  t.isTrue(
    errorFor([
      const FileSize('lib/shrunk.dart', 800),
    ], 'lib/shrunk.dart').contains('entfernen'),
    'unter der Schwelle: Eintrag entfernen ist ein Fehler',
  );
  t.isTrue(
    errorFor(const [], 'lib/gone.dart').contains('nicht mehr vorhanden'),
    'gelöschte Datei: Eintrag entfernen',
  );

  final r = evaluate([
    const FileSize('lib/a.dart', 801),
    const FileSize('lib/b.dart', 601),
    const FileSize('packages/a/lib/testing/c.dart', 2000),
    const FileSize('test/d_test.dart', 1501),
    const FileSize('test/e_test.dart', 1001),
    const FileSize(
      'lib/f.dart',
      10,
      functions: [Measure('long', 1, 151), Measure('mid', 1, 81)],
      classes: [Measure('C', 1, 401)],
    ),
    const FileSize(
      'packages/a/lib/testing/g.dart',
      10,
      functions: [Measure('suite', 1, 300)],
    ),
  ], const {});
  t.eq(r.errors.length, 3, 'Fehler: Datei > 800, Test > 1500, Funktion > 150');
  t.eq(
    r.warnings.length,
    6,
    'Warnungen: 600, lib/testing, Test 1000, Funktion 80, Klasse 400, Suite',
  );
}

void _docPaths(SelfCheck t) {
  t.group('Pfade in der Doku');
  final refs = pathRefs('''
Siehe `app/lib/di/providers.dart`, `agent_runner.dart:720`, `di/`,
`package:wendelin_core/fakes.dart`, `--changed`, `wendelin_core`,
`test/<pfad>`, `/opt/homebrew/bin`, `github.com/x/y` und `fehlt/nicht.dart`.
''');
  t.eq(refs.map((r) => r.path).toList(), [
    'app/lib/di/providers.dart',
    'agent_runner.dart',
    'di/',
    'packages/wendelin_core/lib/fakes.dart',
    'fehlt/nicht.dart',
  ], 'erkannte Pfade');
  final index = RepoIndex([
    'app/lib/di/providers.dart',
    'packages/wendelin_agent/lib/src/agent_runner.dart',
    'packages/wendelin_core/lib/fakes.dart',
    'docs/design/DESIGN.md',
  ]);
  for (final r in refs.take(4)) {
    t.isTrue(index.resolves(r.path), '${r.path} aufgelöst');
  }
  t.isTrue(!index.resolves('fehlt/nicht.dart'), 'fehlender Pfad erkannt');
  t.isTrue(
    index.resolves('design/DESIGN.md', docDir: 'docs'),
    'relativ zum Dokument',
  );
}
