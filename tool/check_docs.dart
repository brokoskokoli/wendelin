// Prüft, dass die Pfadangaben in der Agenten-Doku (Architekturkarte,
// Engineering-Regeln, Paket-READMEs) auf existierende Dateien oder Ordner
// zeigen. Geprüft werden Angaben in `Backticks`, die wie ein Pfad aussehen.
import 'dart:io';

import 'src/doc_paths.dart';

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

void main() {
  final listing = Process.runSync('git', [
    'ls-files',
    '--cached',
    '--others',
    '--exclude-standard',
  ]);
  final files = (listing.stdout as String)
      .split('\n')
      .where((p) => p.isNotEmpty && File(p).existsSync())
      .toList();
  final index = RepoIndex(files);
  final errors = <String>[];
  var count = 0;
  for (final doc in checkedDocs) {
    final f = File(doc);
    if (!f.existsSync()) {
      errors.add('$doc: fehlt');
      continue;
    }
    for (final ref in pathRefs(f.readAsStringSync())) {
      count++;
      if (!index.resolves(ref.path, docDir: _dirOf(doc))) {
        errors.add('$doc:${ref.line}: Pfad `${ref.path}` existiert nicht');
      }
    }
  }
  if (errors.isEmpty) {
    stdout.writeln(
      'check_docs: ok ($count Pfade in ${checkedDocs.length} Dokumenten)',
    );
  } else {
    errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}

String _dirOf(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i);
}
