// Selbsttests von src/doc_check.dart, src/gen_docs.dart und der Linkauflösung
// in src/doc_paths.dart (in einem temporären Projekt).
import 'dart:io';

import 'doc_check.dart';
import 'doc_idents.dart';
import 'doc_paths.dart';
import 'doc_stand.dart';
import 'gen_docs.dart';
import 'gen_docs_tables.dart';
import 'self_check.dart';

const _ok = '# WP1 Eins\n> Stand: gültig\n';

/// Mutation: m5-Datei ohne Stand-Zeile wird gemeldet.
void standChecks(SelfCheck t) {
  t.group('doc_stand');
  final tmp = Directory.systemTemp.createTempSync('doc_stand_');
  try {
    const f = 'docs/testing/m5/wp1.md';
    List<String> errs() =>
        standErrors([f, 'docs/testing/m5/README.md'], root: tmp.path);
    File('${tmp.path}/$f')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_ok);
    t.eq(errs(), <String>[], 'mit Stand-Zeile ohne Befund');
    File('${tmp.path}/$f').writeAsStringSync('# WP1 Eins\n');
    t.eq(errs().length, 1, 'ohne Stand-Zeile rot');
    File('${tmp.path}/$f').writeAsStringSync('# WP1\n> Stand: bald\n');
    t.eq(errs().length, 1, 'ungültiger Stand rot');
    _standFormat(t, (c) {
      File('${tmp.path}/$f').writeAsStringSync(c);
      return errs().length;
    });
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

/// Strenges Stand-Format: Zeile 2, Klammergrund, WP-Nummer; Index-Suffix.
void _standFormat(SelfCheck t, int Function(String) errCount) {
  String doc(String stand, {int line = 2}) =>
      '# WP1\n${line == 2 ? '' : '\n'}> Stand: $stand\n';
  for (final ok in [
    'gültig',
    'teilweise überholt (x)',
    'überholt durch WP12b',
  ]) {
    t.eq(errCount(doc(ok)), 0, 'Stand „$ok“ gültig');
  }
  for (final bad in [
    'teilweise überholt',
    'überholt durch',
    'überholt durch WP',
  ]) {
    t.eq(errCount(doc(bad)), 1, 'Stand „$bad“ rot');
  }
  t.eq(errCount(doc('gültig', line: 3)), 1, 'Stand-Zeile in Zeile 3 rot');
  t.eq(standSuffix(doc('gültig')), '', 'Suffix: gültig leer');
  t.eq(
    standSuffix(doc('teilweise überholt (x)')),
    ' (teilweise überholt)',
    'Suffix: teilweise überholt',
  );
  t.eq(
    standSuffix(doc('überholt durch WP2')),
    ' (überholt)',
    'Suffix: überholt',
  );
}

void docCheckChecks(SelfCheck t) {
  t.group('doc_check');
  final tmp = Directory.systemTemp.createTempSync('doc_check_');
  try {
    final root = tmp.path;
    final files = <String>{};
    void put(String rel, String text) {
      File('$root/$rel')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
      files.add(rel);
    }

    List<String> errors() =>
        checkDocs(files.toList(), root: root).errors..sort();

    put(
      'packages/wendelin_core/pubspec.yaml',
      'name: wendelin_core\ndescription: Kern\ndependencies:\n  meta: any\n',
    );
    put(
      'app/lib/di/integrations/registry.dart',
      "import 'a_spec.dart';\n\nfinal x = [\n  aSpec,\n];\n",
    );
    put('app/lib/di/integrations/a_spec.dart', "const s = Spec(id: 'a');\n");
    put('docs/testing/m5/wp1.md', _ok);
    put('docs/architecture/other.md', '# Anderes\n');
    put('docs/architecture/packages.md', '# Pakete\n');
    put(
      'app/channels.json',
      '{"dartNames":"x","channels":{"app.wendelin/a":{"dart":["app/lib/a.dart"],'
          '"kotlin":["A.kt"],"toKotlin":{"go":{"args":["x"],"returns":"value"}},"toDart":{}}}}',
    );
    put(
      'packages/wendelin_core/lib/src/ports.dart',
      'abstract interface class FooPort {}\nclass RealFoo implements FooPort {}\n'
          'class Widget extends Object {}\n',
    );
    put('docs/architecture/ports.md', '# Ports\n');
    put('docs/architecture/channels.md', '# Kanäle\n');
    put('tool/check_channels.dart', '');
    put('app/lib/a.dart', '');
    put('A.kt', '');
    put('tool/check_deps.dart', '');
    put('tool/regen_generated.sh', '');
    for (final e in generateDocs(root).entries) {
      put(e.key, e.value);
    }
    // Pflichtdokumente, damit nur die geprüften Fehler auftreten.
    for (final d in checkedDocs) {
      put(d, '# $d\n');
    }
    put(
      'docs/architecture/linked.md',
      '[ok](other.md#abschnitt) [ok2](./other.md)\n',
    );
    t.eq(staleGenerated(root), <String>[], 'frisch erzeugt: nichts veraltet');
    t.eq(errors(), <String>[], 'gültige Doku ohne Befund');

    // Mutation: Link auf fehlende Datei (mit Anker).
    put('docs/architecture/linked.md', '[x](gone.md#a)\n');
    t.eq(errors(), [
      'docs/architecture/linked.md:1: Link `gone.md` ist tot',
    ], 'toter Link mit Anker wird gemeldet');
    put('docs/architecture/linked.md', '[ok](other.md#abschnitt)\n');
    t.eq(
      errors(),
      <String>[],
      'Link mit Anker auf vorhandene Datei ist gültig',
    );

    // Mutation: toter Link in einer Gerätetest-Datei (docs/testing/m5/).
    put('docs/testing/m5/wp1.md', '$_ok\n[x](gone.md)\n');
    t.eq(errors(), [
      'docs/testing/m5/wp1.md:4: Link `gone.md` ist tot',
    ], 'toter Link in docs/testing/m5 wird gemeldet');
    put('docs/testing/m5/wp1.md', _ok);
    t.eq(errors(), <String>[], 'm5-Datei nach Korrektur ohne Befund');
    _deadPathInRuleDocs(t, put, errors);
    _identChecks(t, put, errors, root);
    _staleChecks(t, put, errors, root);
  } finally {
    tmp.deleteSync(recursive: true);
  }

  _tableChecks(t);
  t.group('doc_paths linkRefs');
  t.eq(
    [
      for (final r in linkRefs(
        '[a](x.md#h) [b](#h) [c](https://x.y/z) [d](d/)',
      ))
        r.path,
    ],
    ['x.md', 'd/'],
    'Anker abgeschnitten, reine Anker und Web-Links übersprungen',
  );
  final idx = RepoIndex(['docs/a.md', 'docs/sub/b.md']);
  t.isTrue(idx.resolvesLink('sub/b.md', docDir: 'docs'), 'relativer Link');
  t.isTrue(
    idx.resolvesLink('../a.md', docDir: 'docs/sub'),
    '.. wird aufgelöst',
  );
  t.isTrue(!idx.resolvesLink('nope.md', docDir: 'docs'), 'fehlende Datei');
  t.isTrue(
    !idx.resolvesLink('b.md', docDir: 'docs'),
    'kein Suffix-Treffer wie bei Pfadangaben',
  );
}

/// Veraltete, fehlende und nicht indexierte erzeugte Doku wird rot.
void _staleChecks(
  SelfCheck t,
  void Function(String, String) put,
  List<String> Function() errors,
  String root,
) {
  // Mutation: veraltete erzeugte Datei.
  File('$root/docs/architecture/generated/packages.md').writeAsStringSync('x');
  t.eq(staleGenerated(root), [
    'docs/architecture/generated/packages.md',
  ], 'veraltete erzeugte Datei');
  t.isTrue(
    errors().any((e) => e.contains('packages.md: veraltet')),
    'check_docs meldet veraltete erzeugte Datei',
  );
  writeGenerated(root);
  t.eq(errors(), <String>[], 'writeGenerated stellt her');

  // Mutation: fehlende erzeugte Datei.
  File('$root/docs/architecture/generated/integrations.md').deleteSync();
  t.eq(staleGenerated(root), [
    'docs/architecture/generated/integrations.md',
  ], 'fehlende erzeugte Datei');
  writeGenerated(root);

  // Mutation: m5-Datei ohne Indexeintrag.
  put('docs/testing/m5/wp2.md', '# WP2 Zwei\n> Stand: gültig\n');
  t.eq(staleGenerated(root), [
    'docs/testing/m5/README.md',
  ], 'm5-Datei ohne Indexeintrag macht den Index veraltet');
  writeGenerated(root);
  t.isTrue(
    File('$root/docs/testing/m5/README.md')
        .readAsStringSync()
        .contains('- [WP2 Zwei](wp2.md)'),
    'Index nennt die neue Datei',
  );
  t.eq(errors(), <String>[], 'nach regen wieder ohne Befund');
}

/// Ein toter Pfad in Regelquelle, Briefing, Agent-Definition und Review-Protokoll wird rot.
void _deadPathInRuleDocs(
  SelfCheck t,
  void Function(String, String) put,
  List<String> Function() errors,
) {
  for (final d in [
    'AGENTS.md',
    'docs/work-packages/REVIEW.md',
    'docs/agents/coder.md',
    '.claude/agents/wendelin-coder.md',
  ]) {
    put(d, '# $d\n\nSiehe `tool/gone.sh`.\n');
    t.eq(errors(), [
      '$d:3: Pfad `tool/gone.sh` existiert nicht',
    ], 'toter Pfad in $d wird gemeldet');
    put(d, '# $d\n');
    t.eq(errors(), <String>[], '$d nach Korrektur ohne Befund');
  }
  _relativeDeadPath(t, put, errors);
  _conceptDocs(t, put, errors);
}

/// Relativer toter Pfad (ohne Repo-Wurzel) in einem Regel-Dokument ist rot;
/// ein Vermerk „nur im Git-Verlauf“ gilt nur für seine Zeile.
void _relativeDeadPath(
  SelfCheck t,
  void Function(String, String) put,
  List<String> Function() errors,
) {
  const d = 'docs/architecture/x.md';
  put(d, '# x\n\nSiehe `nichtda.md`.\n');
  t.eq(errors(), [
    '$d:3: Pfad `nichtda.md` existiert nicht',
  ], 'relativer toter Pfad in Regel-Dokument wird gemeldet');
  put(d, '# x\n\nalt `gone.md` (nur im Git-Verlauf)\nneu `tool/gone.sh`\n');
  t.eq(errors(), [
    '$d:4: Pfad `tool/gone.sh` existiert nicht',
  ], 'Vermerk „nur im Git-Verlauf“ wirkt nur auf seine Zeile');
  put(d, '# x\n');
}

/// Bezeichner-Check: unbekannter Name rot, bekannter grün, Allowlist ist eine Ratsche.
void _identChecks(
  SelfCheck t,
  void Function(String, String) put,
  List<String> Function() errors,
  String root,
) {
  put('docs/architecture/idents.md', 'Der Typ `GhostThing` und `FooPort`.\n');
  t.eq(errors(), [
    'docs/architecture/idents.md#GhostThing: neu (Bezeichner nicht im Code, 1). '
        'Beheben, nicht in tool/doc_ident_allowlist.yaml eintragen '
        '(die Baseline darf nur schrumpfen).',
  ], 'Bezeichner ohne Treffer im Code wird gemeldet');
  put('packages/wendelin_core/lib/src/ghost.kt', 'class GhostThing\n');
  t.eq(errors(), <String>[], 'Bezeichner im Kotlin-Code gefunden: grün');
  File('$root/packages/wendelin_core/lib/src/ghost.kt').deleteSync();
  put('packages/wendelin_core/lib/src/ghost.kt', '// nichts\n');
  put(
    'tool/doc_ident_allowlist.yaml',
    'docs/architecture/idents.md#GhostThing: 1\n',
  );
  t.eq(errors(), <String>[], 'Bestand in der Allowlist ist erlaubt');
  put('docs/architecture/idents.md', 'Nur `FooPort`.\n');
  t.isTrue(
    errors().join().contains('GhostThing') &&
        errors().join().contains(
          'Eintrag (1) aus tool/doc_ident_allowlist.yaml',
        ),
    'veralteter Allowlist-Eintrag wird zum Entfernen gemeldet',
  );
  File('$root/tool/doc_ident_allowlist.yaml').deleteSync();
  put('docs/architecture/idents.md', '# Leer\n');
  File('$root/packages/wendelin_core/lib/src/ghost.kt').deleteSync();
  t.eq(errors(), <String>[], 'Aufräumen: wieder ohne Befund');
  t.eq(
    camelIdents(
      '`FooBar` `foo()` `FooBar.runNow(x)` `a b` `tool/x.dart` `Port`\n'
      '```\n`Skipped`Too\n```\n',
    ).toList(),
    ['FooBar', 'FooBar', 'runNow'],
    'camelIdents: nur CamelCase-Bezeichner, keine Pfade, Blöcke oder Einzelwörter',
  );
}

/// Ports- und Kanal-Tabelle aus kleinen Beispielen.
void _tableChecks(SelfCheck t) {
  t.group('gen_docs Tabellen');
  final rows = scanPorts({
    'packages/p/lib/src/a.dart':
        'abstract interface class FooPort {}\n'
        'abstract interface class _PrivApi {}\n'
        'abstract interface class Helper {}\n'
        'abstract class NoInterfaceStore {}\n'
        'class Multi<T extends Object> extends Base implements FooPort, BarApi {}\n',
    'packages/p/lib/src/b.dart': 'abstract interface class BarApi {}\n',
    'packages/p/lib/testing/fake_foo.dart':
        'class FakeFooPort implements FooPort {}\n',
    'packages/p/lib/testing/stub_foo.dart':
        'class StubFoo implements FooPort {}\n',
    'app/lib/debug/dev.dart': 'class FileFoo implements FooPort {}\n',
    'app/lib/platform/foo.dart': 'final class AppFoo\n    implements FooPort {}\nclass _Hidden implements FooPort {}\n',
  });
  t.eq(
    [for (final r in rows) r.name],
    ['BarApi', 'FooPort'],
    'nur Port-Namen auf interface-Klassen, sortiert nach Paket und Name',
  );
  if (rows.every((r) => r.name != 'FooPort')) return;
  final foo = rows.firstWhere((r) => r.name == 'FooPort');
  t.eq(
    [for (final i in foo.impls) '${i.name}:${i.fake}'],
    [
      'AppFoo:false',
      'FakeFooPort:true',
      'FileFoo:true',
      'Multi:false',
      'StubFoo:true',
    ],
    'Implementierer (auch mehrzeilig, mit Generics) und Fakes getrennt, private '
    'ignoriert; Pfade testing/ und debug/ zählen als Fake',
  );
  final table = portsTable(rows);
  t.isTrue(
    table.contains('| `FooPort` | `p` |') &&
        table.contains(
          '`FakeFooPort` (`packages/p/lib/testing/fake_foo.dart`)<br>',
        ),
    'Tabelle nennt Port, Paket und Fake in eigener Spalte',
  );
  final ch = channelsTable(
    '{"channels":{"app.wendelin/x":{"dart":["a.dart"],"kotlin":["X.kt"],'
    '"toKotlin":{"go":{"args":["p","q"]}},"toDart":{}}}}',
  );
  t.isTrue(
    ch.contains('| `x` | `a.dart` | `X.kt` | `go(p, q)` | – |'),
    'Kanal-Tabelle: Dateien und Methoden mit Argumenten ($ch)',
  );
}

/// Konzept und Änderungsarchiv: erfundene Repo-Pfade sind rot, Fremdes und
/// als „nur im Git-Verlauf“ gekennzeichnete Dateien nicht.
void _conceptDocs(
  SelfCheck t,
  void Function(String, String) put,
  List<String> Function() errors,
) {
  const concept = 'Voice Agent App – Gesamtkonzept.md';
  put(
    concept,
    '# K\n\nsiehe `docs/gibt-es-nicht.md`, `tools/list`, `Tasks.md`\n',
  );
  t.eq(errors(), [
    '$concept:3: Pfad `docs/gibt-es-nicht.md` existiert nicht',
  ], 'erfundener Pfad im Konzept wird gemeldet, Fremdes nicht');
  put(concept, '# K\n');
  put('docs/concept-changelog/M9.md', 'Plan `docs/work-packages/M9.md`\n');
  t.eq(errors(), [
    'docs/concept-changelog/M9.md:1: Pfad `docs/work-packages/M9.md` existiert nicht',
  ], 'toter Pfad im Änderungsarchiv wird gemeldet');
  put(
    'docs/concept-changelog/M9.md',
    'Plan `docs/work-packages/M9.md` (nur im Git-Verlauf)\n',
  );
  t.eq(errors(), <String>[], '„nur im Git-Verlauf“ ist ausgenommen');
}
