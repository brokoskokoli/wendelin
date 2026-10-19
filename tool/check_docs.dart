// Prüft, dass die Pfadangaben in der Agenten-Doku (Architekturkarte,
// Engineering-Regeln, Paket-READMEs) auf existierende Dateien oder Ordner
// zeigen. Geprüft werden Angaben in `Backticks`, die wie ein Pfad aussehen.
import 'dart:io';

import 'src/doc_check.dart';

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
  final r = checkDocs(files);
  if (r.errors.isEmpty) {
    stdout.writeln('check_docs: ok (${r.count} Pfade in ${r.docs} Dokumenten)');
  } else {
    r.errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}
