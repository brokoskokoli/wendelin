// Prüft, dass die Pfadangaben in der Agenten-Doku (Architekturkarte,
// Engineering-Regeln, Paket-READMEs) auf existierende Dateien oder Ordner
// zeigen. Geprüft werden Angaben in `Backticks`, die wie ein Pfad aussehen.
import 'dart:io';

import 'src/doc_check.dart';
import 'src/ratchet.dart';

void main(List<String> args) {
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
  if (args.contains('--update-baseline')) {
    // Nur senken oder entfernen, nie erhöhen (Ratsche).
    final f = File(identAllowlist);
    final old = f.existsSync() ? f.readAsStringSync() : '';
    f.writeAsStringSync(
      renderBaseline(
        headerOf(old),
        lowerBaseline(unknownDocIdents(files), parseBaseline(old)),
      ),
    );
    stdout.writeln('check_docs: $identAllowlist aktualisiert');
    return;
  }
  final r = checkDocs(files);
  if (r.errors.isEmpty) {
    stdout.writeln('check_docs: ok (${r.count} Pfade in ${r.docs} Dokumenten)');
  } else {
    r.errors.forEach(stderr.writeln);
    exitCode = 1;
  }
}
