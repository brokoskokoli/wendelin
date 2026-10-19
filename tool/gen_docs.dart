// Erzeugt die aus Code ableitbaren Dokumente (Pakete, Integrationen, Index der
// Gerätetests). `--check` schreibt nichts und meldet Veraltetes (Exit 1).
import 'dart:io';

import 'src/gen_docs.dart';

void main(List<String> args) {
  if (args.contains('--check')) {
    final stale = staleGenerated();
    if (stale.isEmpty) {
      stdout.writeln('gen_docs: aktuell');
    } else {
      for (final p in stale) {
        stderr.writeln('$p: veraltet, `dart run tool/gen_docs.dart` ausführen');
      }
      exitCode = 1;
    }
    return;
  }
  final changed = writeGenerated();
  stdout.writeln(
    changed.isEmpty ? 'gen_docs: nichts zu tun' : 'gen_docs: ${changed.join(', ')}',
  );
}
