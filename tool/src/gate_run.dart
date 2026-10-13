// Schrittausführung und Zusammenfassung für `tool/gate.dart`.
//
// Standard ist die kompakte Ausgabe: Die Ausgabe der Unterprozesse wird
// gepuffert, bei Erfolg erscheint je Schritt eine Zeile, bei einem Fehler
// das Ende der gepufferten Ausgabe. Mit `verbose` erben die Unterprozesse
// stdout/stderr wie früher. Die Dauer wird immer gemessen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Ergebnis eines Unterprozesses. [lines] ist im ausführlichen Modus leer.
final class ProcResult {
  /// Erstellt ein Ergebnis.
  const ProcResult(this.exitCode, [this.lines = const []]);

  /// Exit-Code des Prozesses.
  final int exitCode;

  /// Gepufferte Ausgabe (stdout und stderr in Ankunftsreihenfolge).
  final List<String> lines;
}

/// Startet einen Prozess; austauschbar für die Selbsttests.
typedef ProcRunner = Future<ProcResult> Function(
  String exe,
  List<String> args, {
  String? cwd,
  required bool verbose,
});

/// Echter Prozessstart: puffert im kompakten Modus, erbt sonst stdio.
Future<ProcResult> runProcess(
  String exe,
  List<String> args, {
  String? cwd,
  required bool verbose,
}) async {
  if (verbose) {
    final p = await Process.start(
      exe,
      args,
      workingDirectory: cwd,
      mode: ProcessStartMode.inheritStdio,
    );
    return ProcResult(await p.exitCode);
  }
  final p = await Process.start(exe, args, workingDirectory: cwd);
  final lines = <String>[];
  Future<void> drain(Stream<List<int>> s) => s
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach(lines.add);
  await p.stdin.close();
  // Erst lesen, dann warten: sonst blockiert ein voller Pipe-Puffer.
  final drained = Future.wait([drain(p.stdout), drain(p.stderr)]);
  final code = await p.exitCode;
  await drained;
  return ProcResult(code, lines);
}

/// Ergebnis eines Gate-Schritts.
enum Outcome {
  /// Bestanden.
  ok('ok'),

  /// Fehlgeschlagen.
  red('ROT'),

  /// Nicht ausgeführt.
  skipped('übersprungen');

  const Outcome(this.label);

  /// Text in der Zusammenfassung.
  final String label;
}

/// Eine Zeile der Zusammenfassung.
final class StepResult {
  /// Erstellt eine Zeile.
  const StepResult(this.name, this.outcome, this.duration, [this.detail = '']);

  /// Name des Schritts.
  final String name;

  /// Ergebnis.
  final Outcome outcome;

  /// Laufzeit.
  final Duration duration;

  /// Zusatz, z. B. `612 Tests, 99.1 %` oder `12 Warnungen`.
  final String detail;
}

/// Bewertung nach einem Prozess: Zusatztext und ggf. ein Fehlergrund.
typedef StepCheck = ({String detail, String? failure});

/// Führt Schritte aus und sammelt die Ergebnisse.
final class Gate {
  /// Erstellt ein Gate.
  Gate({
    required this.verbose,
    this.runner = runProcess,
    StringSink? out,
    this.tailLines = 200,
  }) : out = out ?? stdout;

  /// Ausführliche Ausgabe (Unterprozesse erben stdout/stderr).
  final bool verbose;

  /// Prozessstart.
  final ProcRunner runner;

  /// Ziel der Ausgabe.
  final StringSink out;

  /// So viele Zeilen der gepufferten Ausgabe erscheinen bei einem Fehler.
  final int tailLines;

  /// Ergebnisse in Ausführungsreihenfolge.
  final results = <StepResult>[];

  /// Führt einen Schritt aus. [check] bewertet das Ergebnis eines
  /// erfolgreichen Prozesses (Testanzahl, Abdeckung, Warnungen).
  Future<bool> step(
    String name,
    String exe,
    List<String> args, {
    String? cwd,
    Future<StepCheck> Function(ProcResult r)? check,
  }) async {
    if (verbose) out.writeln('\n== $name');
    final sw = Stopwatch()..start();
    final r = await runner(exe, args, cwd: cwd, verbose: verbose);
    var detail = '';
    String? failure = r.exitCode == 0 ? null : 'Exit-Code ${r.exitCode}';
    if (check != null) {
      final c = await check(r);
      detail = c.detail;
      failure ??= c.failure;
    }
    sw.stop();
    final outcome = failure == null ? Outcome.ok : Outcome.red;
    record(StepResult(name, outcome, sw.elapsed, detail));
    if (failure != null && !verbose) {
      out.writeln(tail(r.lines, tailLines).map((l) => '  | $l').join('\n'));
      if (r.exitCode == 0) out.writeln('  | $failure');
    } else if (failure != null) {
      out.writeln('$name: $failure');
    }
    return failure == null;
  }

  /// Hält ein Ergebnis fest und meldet es mit einer Zeile.
  void record(StepResult r) {
    results.add(r);
    final d = r.detail.isEmpty ? '' : ', ${r.detail}';
    out.writeln(
      '${r.outcome.label.padRight(4)} ${r.name} (${seconds(r.duration)} s$d)',
    );
  }

  /// Gibt die Zusammenfassung aus und liefert den Exit-Code.
  int finish(Duration total, {List<String> notes = const []}) {
    out.writeln(renderSummary(results, total, notes: notes));
    return results.any((r) => r.outcome == Outcome.red) ? 1 : 0;
  }
}

/// Die letzten [n] Zeilen von [lines], mit Hinweis auf die Gesamtlänge.
List<String> tail(List<String> lines, int n) => lines.length <= n
    ? lines
    : [
        '… ${lines.length - n} von ${lines.length} Zeilen ausgelassen '
            '(vollständig mit --verbose)',
        ...lines.sublist(lines.length - n),
      ];

/// Sekunden mit einer Nachkommastelle.
String seconds(Duration d) => (d.inMilliseconds / 1000).toStringAsFixed(1);

/// Tabelle mit Schritt, Ergebnis, Dauer und Zusatz, danach Gesamtdauer und
/// `GATE GRÜN` bzw. `GATE ROT: <Schritte>`.
String renderSummary(
  List<StepResult> results,
  Duration total, {
  List<String> notes = const [],
}) {
  final w = results.fold(7, (m, r) => r.name.length > m ? r.name.length : m);
  final b = StringBuffer('\n== Zusammenfassung\n');
  for (final n in notes) {
    b.writeln(n);
  }
  b.writeln('${'Schritt'.padRight(w)}  Ergebnis       Dauer  Details');
  for (final r in results) {
    b.writeln(
      '${r.name.padRight(w)}  ${r.outcome.label.padRight(12)} '
              '${seconds(r.duration).padLeft(6)} s  ${r.detail}'
          .trimRight(),
    );
  }
  b.writeln('Gesamtdauer: ${seconds(total)} s');
  final red = [
    for (final r in results)
      if (r.outcome == Outcome.red) r.name,
  ];
  b.write(red.isEmpty ? 'GATE GRÜN' : 'GATE ROT: ${red.join(', ')}');
  return b.toString();
}

/// Zählt Tests aus einer JSON-Reporter-Datei (`--file-reporter json:…`):
/// bestanden, fehlgeschlagen, übersprungen. `null`, wenn die Datei fehlt.
({int passed, int failed, int skipped})? countTests(String jsonPath) {
  final f = File(jsonPath);
  if (!f.existsSync()) return null;
  var passed = 0, failed = 0, skipped = 0;
  for (final line in f.readAsLinesSync()) {
    if (!line.contains('"testDone"')) continue;
    final Object? e;
    try {
      e = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (e is! Map<String, Object?> || e['hidden'] == true) continue;
    if (e['skipped'] == true) {
      skipped++;
    } else if (e['result'] == 'success') {
      passed++;
    } else {
      failed++;
    }
  }
  return (passed: passed, failed: failed, skipped: skipped);
}

/// Kurztext zur Testanzahl, z. B. `612 Tests, 3 übersprungen`.
String testDetail(({int passed, int failed, int skipped})? c) {
  if (c == null) return '';
  final total = c.passed + c.failed;
  return [
    '$total Tests',
    if (c.failed > 0) '${c.failed} rot',
    if (c.skipped > 0) '${c.skipped} übersprungen',
  ].join(', ');
}

/// Zeilenabdeckung in Prozent aus `lcov.info`, ohne generierten Code
/// (`*.g.dart`, `*.steps.dart`) und ohne `lib/testing/`.
double lcovCoverage(Iterable<String> lines) {
  var found = 0, hit = 0;
  var skip = false;
  for (final line in lines) {
    if (line.startsWith('SF:')) {
      final f = line.substring(3);
      skip =
          f.endsWith('.g.dart') ||
          // drift `make-migrations` (generierte Schema-Schritte).
          f.endsWith('.steps.dart') ||
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

/// Bewertung der Abdeckung [cov] gegen [min]; rot darunter.
StepCheck coverageCheck(double cov, String tests, double min) {
  final c = '${cov.toStringAsFixed(1)} %';
  return (
    detail: [if (tests.isNotEmpty) tests, c].join(', '),
    failure: cov < min ? 'Abdeckung $c < $min %' : null,
  );
}
