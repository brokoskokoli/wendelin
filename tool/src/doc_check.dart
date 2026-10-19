// Kern von tool/check_docs.dart: Pfadangaben und Links in der Doku auflösen
// und erzeugte Dateien auf Aktualität prüfen.
import 'dart:io';

import 'doc_paths.dart';
import 'gen_docs.dart';

/// Dokumente, deren Pfadangaben aufgelöst werden müssen.
const checkedDocs = [
  'CLAUDE.md',
  'docs/ARCHITECTURE.md',
  'docs/ENGINEERING.md',
  'packages/wendelin_core/README.md',
  'packages/wendelin_providers/README.md',
  'packages/wendelin_tools/README.md',
  'packages/wendelin_agent/README.md',
];

/// Ergebnis von [checkDocs].
typedef DocCheck = ({List<String> errors, int count, int docs});

/// Prüft die Doku unter [root]; [files] sind die Repo-Dateien relativ zu [root].
DocCheck checkDocs(List<String> files, {String root = '.'}) {
  final index = RepoIndex(files);
  final errors = <String>[];
  var count = 0;
  // Bereichsdateien der Architekturkarte und Gerätetests werden mitgeprüft.
  final docsToCheck = [
    ...checkedDocs,
    for (final f in files)
      if (f.endsWith('.md') &&
          (f.startsWith('docs/architecture/') ||
              f.startsWith('docs/testing/m5/')))
        f,
  ];
  for (final doc in docsToCheck) {
    final f = File('$root/$doc');
    if (!f.existsSync()) {
      errors.add('$doc: fehlt');
      continue;
    }
    final text = f.readAsStringSync();
    for (final ref in pathRefs(text)) {
      count++;
      if (!index.resolves(ref.path, docDir: _dirOf(doc))) {
        errors.add('$doc:${ref.line}: Pfad `${ref.path}` existiert nicht');
      }
    }
    for (final ref in linkRefs(text)) {
      count++;
      if (!index.resolvesLink(ref.path, docDir: _dirOf(doc))) {
        errors.add('$doc:${ref.line}: Link `${ref.path}` ist tot');
      }
    }
  }
  // Erzeugte Dateien (tool/gen_docs.dart) müssen aktuell sein.
  if (File('$root/app/lib/di/integrations/registry.dart').existsSync()) {
    for (final p in staleGenerated(root)) {
      errors.add('$p: veraltet, `dart run tool/gen_docs.dart` ausführen');
    }
  }
  return (errors: errors, count: count, docs: docsToCheck.length);
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
