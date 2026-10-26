// Gate-Schritt: Konzept und Änderungsprotokoll (siehe tool/src/concept_check.dart).
// Bestand: tool/concept_allowlist.yaml.
//
//   dart run tool/check_concept.dart [--update-baseline]
import 'dart:io';

import 'src/concept_check.dart';
import 'src/ratchet.dart';

void main(List<String> args) {
  if (!File(conceptFile).existsSync()) {
    stderr.writeln('check_concept: $conceptFile fehlt');
    exitCode = 1;
    return;
  }
  if (args.contains('--update-baseline')) {
    // Nur senken oder entfernen, nie erhöhen (Ratsche).
    final f = File(conceptAllowlist);
    final old = f.existsSync() ? f.readAsStringSync() : '';
    f.writeAsStringSync(
      renderBaseline(
        headerOf(old),
        lowerBaseline(scanConcept('.').found, parseBaseline(old)),
      ),
    );
    stdout.writeln('check_concept: $conceptAllowlist aktualisiert');
    return;
  }
  final errors = conceptErrors('.');
  if (errors.isEmpty) {
    final n = parseBaseline(
      File(conceptAllowlist).existsSync()
          ? File(conceptAllowlist).readAsStringSync()
          : '',
    ).length;
    stdout.writeln('check_concept: ok ($n Einträge auf der Ausnahmeliste)');
    return;
  }
  errors.forEach(stderr.writeln);
  exitCode = 1;
}
