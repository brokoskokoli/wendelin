// Kern von tool/check_concept.dart (WP147): zwei Prüfungen am Konzept.
//  1. Jede bestätigte K-Nummer (Konzept und Archiv) kommt im Konzepttext in
//     Klammern vor, z. B. „(K12)“ oder „(offline, K7)“, oder in einer ADR.
//  2. Nennt STATUS.md einen K-Status („K59 bestätigt“, „K81 offen“), muss er
//     zum Status im Konzept (Tabelle oder Archiv) passen.
// Bestand steht in `tool/concept_allowlist.yaml` (Ratsche, nur abbauen), die
// Schlüssel tragen das Präfix `ref/` (Prüfung 1) bzw. `status/` (Prüfung 2).
import 'dart:io';

import 'concept_log.dart';
import 'ratchet.dart';

/// Dateien, relativ zum Wurzelordner.
const conceptFile = 'Voice Agent App – Gesamtkonzept.md';

/// Bestand beider Prüfungen.
const conceptAllowlist = 'tool/concept_allowlist.yaml';

/// Gefundene Verstöße (`ref/K12`, `status/K81` → Anzahl) und Fehlertexte.
typedef ConceptScan = ({Map<String, int> found, Map<String, String> notes});

String _read(String root, String path) => File('$root/$path').existsSync()
    ? File('$root/$path').readAsStringSync()
    : '';

/// Liest Konzept, Archiv, ADRs und STATUS unter [root] und berechnet die
/// Verstöße ohne Allowlist.
ConceptScan scanConcept(String root) {
  final concept = _read(root, conceptFile);
  final archive = Directory('$root/$archiveDir');
  final texts = [
    concept,
    if (archive.existsSync())
      for (final f in archive.listSync().whereType<File>())
        if (RegExp(r'M\d+\.md$').hasMatch(f.path)) f.readAsStringSync(),
  ];
  final status = statusByNr(texts);
  final adrDir = Directory('$root/docs/adr');
  final adrs = [
    if (adrDir.existsSync())
      for (final f in adrDir.listSync().whereType<File>())
        if (f.path.endsWith('.md')) f.readAsStringSync(),
  ];
  final referenced = referencedNrs(conceptBody(concept), adrs);
  final found = <String, int>{};
  for (final n in confirmedNrs(status)) {
    if (!referenced.contains(n)) found['ref/K$n'] = 1;
  }
  final mentions = statusMentions(_read(root, 'docs/work-packages/STATUS.md'));
  final notes = <String, String>{};
  for (final e in mentions.entries) {
    final s = status[e.key];
    final kind = s == null ? null : statusKind(s);
    if (kind != e.value.word) {
      found['status/K${e.key}'] = 1;
      notes['status/K${e.key}'] =
          'docs/work-packages/STATUS.md:${e.value.line}: K${e.key} '
          '„${e.value.word}“, im Konzept ${s == null ? 'nicht vorhanden' : '„$kind“'}';
    }
  }
  return (found: found, notes: notes);
}

/// Fehler beider Prüfungen unter [root] gegen die Allowlist.
List<String> conceptErrors(String root) {
  final scan = scanConcept(root);
  final baseline = parseBaseline(_read(root, conceptAllowlist));
  const whats = {
    'ref/': 'bestätigter Eintrag ohne „(Knn)“ im Konzepttext und ohne ADR',
    'status/': 'K-Status weicht von STATUS.md ab',
  };
  final errors = <String>[];
  for (final MapEntry(key: prefix, value: what) in whats.entries) {
    Map<String, int> only(Map<String, int> m) => {
      for (final e in m.entries)
        if (e.key.startsWith(prefix)) e.key.substring(prefix.length): e.value,
    };
    errors.addAll(
      ratchetErrors(
        only(scan.found),
        only(baseline),
        what: what,
        file: '$conceptAllowlist (Schlüssel $prefix…)',
        fix: 'dart run tool/check_concept.dart --update-baseline',
      ).map((e) {
        final key = '$prefix${e.split(':').first}';
        return baseline.containsKey(key) ? e : (scan.notes[key] ?? e);
      }),
    );
  }
  return errors;
}
