// Selbsttests von src/doc_check.dart, src/gen_docs.dart und der Linkauflösung
// in src/doc_paths.dart (in einem temporären Projekt).
import 'dart:io';

import 'doc_check.dart';
import 'doc_paths.dart';
import 'gen_docs.dart';
import 'self_check.dart';

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
    put('docs/testing/m5/wp1.md', '# WP1 Eins\n');
    put('docs/architecture/other.md', '# Anderes\n');
    put('docs/architecture/packages.md', '# Pakete\n');
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

    // Mutation: veraltete erzeugte Datei.
    File('$root/docs/architecture/generated/packages.md')
        .writeAsStringSync('x');
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
    put('docs/testing/m5/wp2.md', '# WP2 Zwei\n');
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
  } finally {
    tmp.deleteSync(recursive: true);
  }

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
