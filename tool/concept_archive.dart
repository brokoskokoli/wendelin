// Verschiebt bestätigte Einträge des Änderungsprotokolls aus dem Konzept in
// `docs/concept-changelog/M<n>.md` (Regel für <n>: Kopf von
// `tool/src/concept_log.dart`). Offene, zurückgestellte und teilweise
// bestätigte Einträge bleiben im Konzept. Ohne `--apply` nur Vorschau;
// idempotent (zweiter Lauf ändert nichts).
//
//   dart run tool/concept_archive.dart [--apply] [--concept=<datei>]
//       [--status=<STATUS.md>] [--out=<ordner>]
import 'dart:convert';
import 'dart:io';

import 'src/concept_log.dart';

const _concept = 'Voice Agent App – Gesamtkonzept.md';

void main(List<String> args) => exitCode = _run(args);

int _run(List<String> args) {
  String opt(String name, String def) {
    final a = args.where((a) => a.startsWith('--$name=')).firstOrNull;
    return a == null ? def : a.substring(name.length + 3);
  }

  final apply = args.contains('--apply');
  final conceptFile = File(opt('concept', _concept));
  final statusFile = File(opt('status', 'docs/work-packages/STATUS.md'));
  final out = Directory(opt('out', archiveDir));
  for (final f in [conceptFile, statusFile]) {
    if (!f.existsSync()) {
      stderr.writeln('concept_archive: ${f.path} fehlt');
      return 1;
    }
  }
  final map = MilestoneMap.fromStatus(statusFile.readAsStringSync());
  if (map.isEmpty) {
    stderr.writeln(
      'concept_archive: keine Meilenstein-Tabelle in ${statusFile.path}',
    );
    return 1;
  }
  final concept = conceptFile.readAsStringSync();
  final plan = planArchive(concept, map);
  final before = _bytes(concept);
  final after = _bytes(plan.concept);
  final n = plan.moved.values.fold(0, (a, l) => a + l.length);
  final ms = plan.moved.keys.toList()..sort();
  stdout.writeln(
    '${apply ? 'Archiviere' : 'Vorschau (ohne --apply):'} $n Einträge, '
    '${plan.kept.length} bleiben (K${plan.kept.join(', K')}).',
  );
  for (final m in ms) {
    final nrs = [for (final e in plan.moved[m]!) e.nr]..sort();
    stdout.writeln('  M$m: ${nrs.length} (K${nrs.first}–K${nrs.last})');
  }
  stdout.writeln('Konzept: $before Byte -> $after Byte');
  if (!apply) return 0;
  out.createSync(recursive: true);
  final files = <String, String>{};
  for (final f in out.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (RegExp(r'^M\d+\.md$').hasMatch(name)) {
      files[name] = f.readAsStringSync();
    }
  }
  for (final m in ms) {
    final name = 'M$m.md';
    files[name] = renderArchive(m, files[name] ?? '', plan.moved[m]!);
  }
  void write(String name, String text) {
    final f = File('${out.path}/$name');
    if (!f.existsSync() || f.readAsStringSync() != text) {
      f.writeAsStringSync(text);
    }
  }

  for (final e in files.entries) {
    write(e.key, e.value);
  }
  write('README.md', renderIndex(files));
  if (plan.concept != concept) conceptFile.writeAsStringSync(plan.concept);
  return 0;
}

int _bytes(String s) => utf8.encode(s).length;
