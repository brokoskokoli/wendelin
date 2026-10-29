// Kern von tool/check_docs.dart: Pfadangaben und Links in der Doku auflösen
// und erzeugte Dateien auf Aktualität prüfen.
import 'dart:io';

import 'doc_idents.dart';
import 'doc_paths.dart';
import 'doc_stand.dart';
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
  'Voice Agent App – Gesamtkonzept.md',
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
              f.startsWith('docs/concept-changelog/') ||
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
      if (_inHistory(text, ref.line)) continue;
      if (_rootedOnly(doc) && !index.hasTopLevel(ref.path)) continue;
      count++;
      if (!index.resolves(ref.path, docDir: _dirOf(doc))) {
        errors.add('$doc:${ref.line}: Pfad `${ref.path}` existiert nicht');
      }
    }
    for (final ref in linkRefs(text)) {
      if (_inHistory(text, ref.line)) continue;
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
  errors.addAll(standErrors(files, root: root));
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

/// Konzept und Änderungsarchiv nennen auch Fremdes (Notizen, MCP-Methoden,
/// Netze, Modellnamen): dort zählen nur Pfade, die mit einem Repo-Ordner oder
/// einer Repo-Datei auf oberster Ebene beginnen.
bool _rootedOnly(String doc) =>
    doc.startsWith('Voice Agent App') ||
    doc.startsWith('docs/concept-changelog/');

/// Zeilen mit „(nur im Git-Verlauf)“ nennen bewusst gelöschte Dateien
/// (Archiv `docs/concept-changelog/`) und werden nicht aufgelöst.
bool _inHistory(String text, int line) =>
    text.split('\n')[line - 1].contains('nur im Git-Verlauf');

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}

/// m5-Anleitungen ohne gültige Stand-Zeile (zweite Zeile).
List<String> standErrors(List<String> files, {String root = '.'}) => [
  for (final f in files)
    if (f.startsWith('docs/testing/m5/') &&
        f.endsWith('.md') &&
        !f.endsWith('/README.md') &&
        File('$root/$f').existsSync() &&
        standOf(File('$root/$f').readAsStringSync()) == null)
      '$f:2: Stand-Zeile fehlt (`> Stand: gültig | teilweise überholt (…) | '
          'überholt durch WPnn`)',
];
