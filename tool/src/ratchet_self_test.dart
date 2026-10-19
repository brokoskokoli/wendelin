// Selbsttests der Ratsche (WP109): Größenwarnungen und ignore-Budget.
import 'dart:io';

import 'ignore_scan.dart';
import 'ratchet.dart';
import 'self_check.dart';
import 'size_rules.dart';

/// Ein ignore-Kommentar, zur Laufzeit gebaut (sonst zählt ihn der Check selbst).
String _ig(String rest, {bool file = false}) =>
    '// ${file ? 'ignore_for_file' : 'ignore'}: $rest';

void ratchetChecks(SelfCheck t) {
  _pure(t);
  _ignoreCount(t);
  final tool = File('tool').absolute.path;
  final d = Directory.systemTemp.createTempSync('ratchet_selftest_');
  try {
    final dir = _Dir(d.path, tool);
    _sizesExit(t, dir);
    _ignoresExit(t, dir);
  } finally {
    d.deleteSync(recursive: true);
  }
}

void _pure(SelfCheck t) {
  t.group('Ratsche (rein)');
  final base = parseBaseline('''
# Kopf
a.dart: 700
b.dart#C.f: 90
ignore/avoid_print: 3
''');
  t.eq(base['b.dart#C.f'], 90, 'Schlüssel mit # und Zahl gelesen');
  List<String> run(Map<String, int> cur) =>
      ratchetErrors(cur, base, what: 'x', file: 'f.yaml', fix: 'cmd');
  t.eq(run(base), <String>[], 'unverändert ist grün');
  t.isTrue(
    run({...base, 'neu.dart': 650}).join('\n').contains('neu.dart: neu'),
    'neue Warnung ist rot',
  );
  t.isTrue(
    run({...base, 'a.dart': 701}).join('\n').contains('gewachsen'),
    'Wachstum über den Wert ist rot',
  );
  t.isTrue(
    run({...base, 'a.dart': 650}).join('\n').contains('senken'),
    'unter dem Wert ist rot (Baseline senken)',
  );
  t.isTrue(
    run({'a.dart': 700, 'ignore/avoid_print': 3})
        .join('\n')
        .contains('entfernen'),
    'veralteter Eintrag ist rot',
  );
  final cur = {
    'a.dart': 650,
    'b.dart#C.f': 95,
    'neu.dart': 700,
    'ignore/avoid_print': 3,
  };
  final low = lowerBaseline(cur, base);
  t.eq(low, {
    'a.dart': 650,
    'b.dart#C.f': 90,
    'ignore/avoid_print': 3,
  }, 'update: senkt, erhöht nie, nimmt Neues nicht auf, entfernt Veraltetes');
  t.eq(
    parseBaseline(renderBaseline(headerOf('# K1\n# K2\nx: 1\n'), low)),
    low,
    'Baseline-Datei rundet',
  );
}

void _ignoreCount(SelfCheck t) {
  t.group('ignore-Zählung');
  final text = [
    _ig('avoid_print  weil darum'),
    'foo(); ${_ig('close_sinks, cancel_subscriptions')}',
    '/// Doku zu ${_ig('lauter_text_hier')}',
    _ig('type=lint, public_member_api_docs', file: true),
    _ig('see Begründung, wird so gemacht'),
  ].join('\n');
  t.eq(countIgnores(text), {
    'ignore/avoid_print': 1,
    'ignore/close_sinks': 1,
    'ignore/cancel_subscriptions': 1,
    'ignore_for_file/type=lint': 1,
    'ignore_for_file/public_member_api_docs': 1,
    'ignore/see': 1,
  }, 'Regeln je Art gezählt, Doku-Kommentare und Fließtext nicht');
  t.isTrue(
    isGenerated('app/lib/l10n/gen/a.dart') &&
        isGenerated('app/lib/platform/attest/generated/q.dart') &&
        isGenerated('app/lib/x/frb_generated.web.dart') &&
        !isGenerated('app/lib/ui/a.dart'),
    'erzeugter Code ausgenommen',
  );
  final r = evaluate([const FileSize('packages/a/lib/a.dart', 650)], {});
  t.eq(r.warned, {'packages/a/lib/a.dart': 650}, 'evaluate: Warnschlüssel');
}

/// Ein Wegwerf-Ordner, in dem die Prüfskripte laufen.
final class _Dir {
  _Dir(this.path, this.tool);

  final String path;
  final String tool;

  void write(String f, String text) =>
      (File('$path/$f')..createSync(recursive: true)).writeAsStringSync(text);

  String read(String f) => File('$path/$f').readAsStringSync();

  void delete(String f) => File('$path/$f').deleteSync();

  ProcessResult run(String script, [List<String> args = const []]) =>
      Process.runSync('dart', [
        'run',
        '$tool/$script',
        ...args,
      ], workingDirectory: path);
}

void _sizesExit(SelfCheck t, _Dir d) {
  t.group('Ratsche Größen (Exit-Codes)');
  const big = 'packages/x/lib/a.dart';
  const baseline = 'tool/size_warn_baseline.yaml';
  const gen = 'app/lib/l10n/gen/app_localizations_de.dart';
  d.write(gen, '// x\n' * 700);
  t.eq(
    d.run('check_sizes.dart').exitCode,
    0,
    'erzeugte Datei (l10n gen/) über der Schwelle: ohne Baseline grün',
  );
  d.write(gen, '// x\n' * 701);
  t.eq(d.run('check_sizes.dart').exitCode, 0, 'erzeugte Datei +1 Zeile: grün');
  d.delete(gen);
  d.write(big, '// x\n' * 601);
  var res = d.run('check_sizes.dart');
  t.isTrue(
    res.exitCode == 1 && '${res.stderr}'.contains('$big: neu'),
    'neue Größenwarnung ist rot: ${res.stderr}',
  );
  d.write(baseline, '# Kopf\n$big: 601\n');
  t.eq(d.run('check_sizes.dart').exitCode, 0, 'Baseline deckt die Warnung');
  d.write(big, '// x\n' * 650);
  t.eq(d.run('check_sizes.dart').exitCode, 1, 'gewachsene Warnung ist rot');
  res = d.run('check_sizes.dart', ['--update-baseline']);
  t.isTrue(
    res.exitCode == 1 && d.read(baseline).contains('$big: 601'),
    '--update-baseline erhöht nie',
  );
  d.write(baseline, '# Kopf\n$big: 650\n');
  d.write(big, '// x\n' * 610);
  res = d.run('check_sizes.dart');
  t.isTrue(
    res.exitCode == 1 && '${res.stderr}'.contains('senken'),
    'geschrumpfte Warnung ist rot, bis die Baseline sinkt',
  );
  d.write('packages/x/lib/b.dart', '// y\n' * 700);
  d.run('check_sizes.dart', ['--update-baseline']);
  t.isTrue(
    d.read(baseline).contains('$big: 610') &&
        !d.read(baseline).contains('b.dart'),
    '--update-baseline senkt, nimmt Neues nicht auf',
  );
  d.delete('packages/x/lib/b.dart');
  t.eq(d.run('check_sizes.dart').exitCode, 0, 'nach dem Senken grün');
  d.delete(big);
  res = d.run('check_sizes.dart');
  t.isTrue(
    res.exitCode == 1 && '${res.stderr}'.contains('entfernen'),
    'veralteter Baseline-Eintrag ist rot',
  );
}

void _ignoresExit(SelfCheck t, _Dir d) {
  t.group('Ratsche ignore-Budget (Exit-Codes)');
  const budget = 'tool/ignore_budget.yaml';
  final one = '${_ig('avoid_print')}\n';
  d.write('app/lib/ui/a.dart', one * 2);
  d.write('app/lib/l10n/gen/g.dart', '$one${_ig('type=lint', file: true)}\n');
  final res = d.run('check_ignores.dart');
  t.isTrue(
    res.exitCode == 1 && '${res.stderr}'.contains('ignore/avoid_print: neu'),
    'neues ignore ohne Budget ist rot: ${res.stderr}',
  );
  d.write(budget, '# Kopf\nignore/avoid_print: 2\n');
  t.eq(
    d.run('check_ignores.dart').exitCode,
    0,
    'Budget 2 reicht (Erzeugtes ausgenommen)',
  );
  d.write('app/lib/ui/b.dart', one);
  t.eq(d.run('check_ignores.dart').exitCode, 1, 'ignore über Budget ist rot');
  d.run('check_ignores.dart', ['--update-baseline']);
  t.isTrue(d.read(budget).contains('avoid_print: 2'), 'Budget wird nie erhöht');
  d.delete('app/lib/ui/b.dart');
  d.write('app/lib/ui/a.dart', one);
  t.eq(d.run('check_ignores.dart').exitCode, 1, 'ignore unter Budget ist rot');
  d.run('check_ignores.dart', ['--update-baseline']);
  t.isTrue(
    d.read(budget).contains('avoid_print: 1') &&
        d.run('check_ignores.dart').exitCode == 0,
    'Budget wird gesenkt, danach grün',
  );
}
