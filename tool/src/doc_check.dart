// Kern von tool/check_docs.dart: Pfadangaben und Links in der Doku auflösen
// und erzeugte Dateien auf Aktualität prüfen.
import 'dart:io';

import 'doc_idents.dart';
import 'doc_paths.dart';
import 'gen_docs.dart';
import 'ratchet.dart';

/// Dokumente, deren Pfadangaben aufgelöst werden müssen.
const checkedDocs = [
  'AGENTS.md',
  'CLAUDE.md',
  'docs/ARCHITECTURE.md',
  'docs/ENGINEERING.md',
  'docs/RELEASE.md',
  'PROJECT.md',
  'docs/work-packages/README.md',
  'docs/work-packages/REVIEW.md',
  'packages/wendelin_core/README.md',
  'packages/wendelin_providers/README.md',
  'packages/wendelin_tools/README.md',
  'packages/wendelin_agent/README.md',
  'packages/wendelin_mcp/README.md',
  'packages/wendelin_storage/README.md',
  'packages/wendelin_voice/README.md',
];

/// Ergebnis von [checkDocs].
typedef DocCheck = ({List<String> errors, int count, int docs});

/// Prüft die Doku unter [root]; [files] sind die Repo-Dateien relativ zu [root].
DocCheck checkDocs(List<String> files, {String root = '.'}) {
  final index = RepoIndex(files);
  final errors = <String>[];
  var count = 0;
  // Bereichsdateien der Architekturkarte, Gerätetests und Rollen-Briefings
  // (docs/agents/, .claude/agents/) werden mitgeprüft.
  final docsToCheck = [
    ...checkedDocs,
    for (final f in files)
      if (f.endsWith('.md') &&
          (f.startsWith('docs/architecture/') ||
              f.startsWith('docs/testing/m5/') ||
              f.startsWith('docs/agents/') ||
              f.startsWith('.claude/agents/')))
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
  errors.addAll(identErrors(files, root: root));
  return (errors: errors, count: count, docs: docsToCheck.length);
}

/// Datei mit dem Bestand unbekannter Bezeichner (Ratsche, nur abbauen).
const identAllowlist = 'tool/doc_ident_allowlist.yaml';

/// Ob [path] zu den Dokumenten des Bezeichner-Checks gehört.
bool _isIdentDoc(String path) =>
    path.startsWith('docs/architecture/') &&
    path.endsWith('.md') &&
    !path.contains('/generated/');

/// Unbekannte Bezeichner (`<doc>#<name>` → Anzahl) in der Architekturdoku
/// gegenüber dem Code (Dart, Kotlin, Rust) unter [root].
Map<String, int> unknownDocIdents(List<String> files, {String root = '.'}) {
  final code = <String>{};
  final docs = <String, String>{};
  for (final f in files) {
    final isCode =
        f.endsWith('.dart') || f.endsWith('.kt') || f.endsWith('.rs');
    final isDoc = _isIdentDoc(f);
    if (!isCode && !isDoc) continue;
    final file = File('$root/$f');
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    if (isCode) addCodeWords(text, code);
    if (isDoc) docs[f] = text;
  }
  return unknownIdents(docs, code);
}

/// Fehler des Bezeichner-Checks gegen die Allowlist unter [root].
List<String> identErrors(List<String> files, {String root = '.'}) {
  final list = File('$root/$identAllowlist');
  final allowed = list.existsSync()
      ? parseBaseline(list.readAsStringSync())
      : <String, int>{};
  return ratchetErrors(
    unknownDocIdents(files, root: root),
    allowed,
    what: 'Bezeichner nicht im Code',
    file: identAllowlist,
    fix: 'dart run tool/check_docs.dart --update-baseline',
  );
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
