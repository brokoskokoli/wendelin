// Selbsttests von tool/src/concept_log.dart, tool/src/concept_check.dart und
// tool/concept_archive.dart (WP147) in einem temporären Projekt.
import 'dart:io';

import 'concept_check.dart';
import 'concept_log.dart';
import 'self_check.dart';

const _status = '''
## Meilensteine

| Meilenstein | Pakete | Status |
| --- | --- | --- |
| M0 Gerüst, M1 Text-Agent | WP01–WP14 | erledigt |
| M2 Sprache | WP15–WP20 | erledigt |
| M4 Wake Word | WP41–WP78, WP80 | erledigt |
| M5 Ausbau | WP76b–d, WP79, WP81–WP98 | in Arbeit |
| M6 Ausbau 2 | WP99–WP101 | in Arbeit |

## M5 im Detail

| Paket | Titel | Status | Offen |
| --- | --- | --- | --- |
| WP88 | Aufgaben | gemergt | – |
''';

String _row(int n, String date, String ground, String status) =>
    '| K$n | $date | Abschnitt | **Titel** Text (K$n). | $ground | $status |';

String _concept(List<String> rows) =>
    '''
# Konzept

Text (K1) und (offline, K2) und (K3).

## Änderungsprotokoll

Abweichungen, die sich bei der Umsetzung ergeben.

| Nr. | Datum | Abschnitt | Änderung | Grund | Status |
| --- | --- | --- | --- | --- | --- |
${rows.join('\n')}
''';

final _rows = [
  _row(1, '2026-10-13', 'Review WP01', 'bestätigt 2026-10-13'),
  _row(2, '2026-10-16', 'Gerätetest 2026-10-16', 'bestätigt 2026-10-16'),
  _row(3, '2026-10-18', 'Entscheidung Maintainer', 'bestätigt 2026-10-18'),
  _row(4, '2026-10-18', 'WP91 Umsetzung', 'bestätigt 2026-10-18'),
  _row(5, '2026-10-19', 'WP88', 'offen'),
  _row(6, '2026-10-19', 'WP79', 'bestätigt 2026-10-19, Umfang offen'),
  _row(7, '2026-10-19', 'WP76b', '(1) bestätigt; (2) offen'),
  _row(8, '2026-10-19', 'WP88', 'bestätigt (vorher: offen)'),
  _row(9, '2026-10-20', 'WP101', 'zurückgestellt'),
];

void conceptChecks(SelfCheck t) {
  t.group('concept_log');
  _log(t);
  final tmp = Directory.systemTemp.createTempSync('concept_check_');
  try {
    t.group('check_concept');
    _check(t, tmp.path);
    t.group('concept_archive');
    _archiveTool(t, tmp.path);
  } finally {
    tmp.deleteSync(recursive: true);
  }
}

void _log(SelfCheck t) {
  // Zeilen mit „|“ in Backticks (K56) und Zellen mit „ | “ nicht verlieren.
  final pipe = parseEntries([
    '| K56 | 2026-10-18 | TEE | **NRAS** `a|b` bleibt. | Gerätetest | bestätigt 2026-10-18 |',
    'kein Eintrag',
    '| K57 | zu | kurz |',
  ]);
  t.eq(pipe.map((e) => e.nr).toList(), [
    56,
  ], 'parseEntries: nur vollständige Zeilen');
  t.eq(pipe.single.ground, 'Gerätetest', 'parseEntries: Grund');
  t.eq(pipe.single.status, 'bestätigt 2026-10-18', 'parseEntries: Status');

  t.isTrue(isArchivable('bestätigt 2026-10-13'), 'bestätigt ist archivierbar');
  t.isTrue(
    isArchivable('bestätigt (vorher: offen)'),
    '„vorher: offen“ zählt nicht',
  );
  t.isTrue(!isArchivable('offen'), 'offen bleibt');
  t.isTrue(!isArchivable('zurückgestellt'), 'zurückgestellt bleibt');
  t.isTrue(
    !isArchivable('bestätigt 2026-10-13, Umfang offen'),
    'bestätigt mit offenem Rest bleibt',
  );
  t.isTrue(
    !isArchivable('(1) bestätigt; (2) offen'),
    'gemischter Status bleibt',
  );

  _milestones(t);
}

void _milestones(SelfCheck t) {
  final map = MilestoneMap.fromStatus(_status);
  t.isTrue(!map.isEmpty, 'MilestoneMap liest die Tabelle');
  t.isTrue(MilestoneMap.fromStatus('# nichts').isEmpty, 'ohne Tabelle leer');
  t.eq(map.of(1), 1, 'WP01 (Zeile „M0 …, M1 …“) gilt der letzte');
  t.eq(map.of(76), 5, 'WP76 in M4 und M5: die spätere Zeile gewinnt');
  t.eq(map.of(80), 4, 'WP80 steht einzeln in M4');
  t.eq(map.of(110), 6, 'unbekanntes Paket: nächstkleineres aufgeführtes');
  t.eq(map.of(60), 4, 'WP60 liegt in der Spanne WP41–WP78');

  final es = parseEntries(_concept(_rows).split('\n'));
  final ms = assignMilestones(es, map);
  t.eq(ms[1], 1, 'Paketnummer im Grund bestimmt den Meilenstein');
  t.eq(ms[2], 1, 'ohne Paketnummer: Vorgänger, wenn Datum anders');
  t.eq(ms[3], 5, 'ohne Paketnummer: nächster am selben Datum (M5-Start)');
  t.eq(ms[4], 5, 'WP91 gehört zu M5');
  t.eq(ms[9], 6, 'WP101 gehört zu M6');

  final plan = planArchive(_concept(_rows), map);
  t.eq(plan.kept, [
    5,
    6,
    7,
    9,
  ], 'bleiben: offen, Umfang offen, gemischt, zurückgestellt');
  t.eq(plan.moved.keys.toList()..sort(), [1, 5], 'archiviert in M1 und M5');
  t.eq(plan.moved[5]!.map((e) => e.nr).toList(), [3, 4, 8], 'M5-Einträge');
  t.isTrue(
    !plan.concept.contains('| K1 |') && plan.concept.contains('| K5 |'),
    'archivierte Zeilen weg, offene bleiben',
  );
  t.isTrue(
    plan.concept.contains('Archiv `$archiveDir/`'),
    'Verweiszeile im Konzept',
  );
  final again = planArchive(plan.concept, map);
  t.eq(again.concept, plan.concept, 'zweiter Lauf ändert das Konzept nicht');
  t.eq(again.moved, <int, List<KEntry>>{}, 'zweiter Lauf archiviert nichts');

  final once = renderArchive(5, '', plan.moved[5]!);
  t.eq(
    renderArchive(5, once, plan.moved[5]!),
    once,
    'renderArchive ist idempotent (Union statt Anhängen)',
  );
  t.eq(
    parseEntries(renderArchive(5, once, [es[4]]).split('\n'))
        .map((e) => e.nr)
        .toList(),
    [3, 4, 5, 8],
    'renderArchive hält bestehende Zeilen und sortiert nach Nummer',
  );
}

void _check(SelfCheck t, String root) {
  void put(String rel, String text) => File('$root/$rel')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
  List<String> errors() => conceptErrors(root);

  final rows = [
    _row(1, '2026-10-13', 'Review WP01', 'bestätigt 2026-10-13'),
    _row(2, '2026-10-13', 'Review WP01', 'offen'),
  ];
  put(conceptFile, _concept(rows));
  put('docs/work-packages/STATUS.md', _status);
  t.eq(errors(), <String>[], 'Verweis (K1) vorhanden: grün');

  // ref: bestätigte Nummer ohne Verweis im Text.
  put(conceptFile, _concept(rows).replaceFirst('Text (K1) und', 'Text und'));
  t.eq(
    errors().length,
    1,
    'bestätigter Eintrag ohne „(Knn)“ im Konzepttext: rot',
  );
  t.isTrue(
    errors().first.contains('ref') || errors().first.contains('K1'),
    'Fehler nennt K1',
  );
  put('docs/adr/0001-x.md', 'Siehe K1 hier.\n');
  t.eq(errors(), <String>[], 'Verweis in einer ADR genügt');
  File('$root/docs/adr/0001-x.md').deleteSync();
  put(conceptFile, _concept(rows).replaceFirst('Text (K1) und', 'Text K1 und'));
  t.eq(errors().length, 1, 'K1 ohne Klammern zählt nicht');
  put('tool/concept_allowlist.yaml', 'ref/K1: 1\n');
  t.eq(errors(), <String>[], 'Bestand in der Allowlist ist erlaubt');
  put(conceptFile, _concept(rows));
  t.isTrue(
    errors().join().contains('K1'),
    'veralteter Allowlist-Eintrag wird zum Entfernen gemeldet',
  );
  File('$root/tool/concept_allowlist.yaml').deleteSync();

  // status: STATUS.md nennt „K2 bestätigt“, das Konzept „offen“.
  put(
    'docs/work-packages/STATUS.md',
    '$_status\nBeleg: K2 bestätigt und K1, K9 offen.\n',
  );
  final e = errors();
  t.isTrue(
    e.any((x) => x.contains('K2') && x.contains('bestätigt')),
    'STATUS „K2 bestätigt“ gegen Konzept „offen“: rot',
  );
  t.isTrue(
    e.any((x) => x.contains('K1') && x.contains('offen')),
    'STATUS „K1 offen“ gegen Konzept „bestätigt“: rot (Listen)',
  );
  t.isTrue(
    e.any((x) => x.contains('K9') && x.contains('nicht vorhanden')),
    'STATUS nennt unbekannte Nummer: rot',
  );
  put(
    'docs/work-packages/STATUS.md',
    '$_status\nBeleg: K1 bestätigt, K2 offen.\n',
  );
  t.eq(errors(), <String>[], 'passender STATUS: grün');

  // Archiv zählt mit: K1 steht nur im Archiv, Verweis bleibt im Text.
  put('$archiveDir/M1.md', '${archiveHead(1)}${rows.first}\n');
  put(conceptFile, _concept([rows[1]]));
  t.eq(errors(), <String>[], 'Status aus dem Archiv wird gelesen');
}

void _archiveTool(SelfCheck t, String root) {
  final dir = Directory('$root/arch')..createSync();
  File('${dir.path}/k.md').writeAsStringSync(_concept(_rows));
  File('${dir.path}/s.md').writeAsStringSync(_status);
  final script = File('tool/concept_archive.dart').absolute.path;
  ProcessResult run(List<String> a) => Process.runSync('dart', [
    'run',
    script,
    '--concept=${dir.path}/k.md',
    '--status=${dir.path}/s.md',
    '--out=${dir.path}/out',
    ...a,
  ]);
  final dry = run([]);
  t.eq(dry.exitCode, 0, 'concept_archive ohne --apply: Exit 0');
  t.isTrue('${dry.stdout}'.contains('Vorschau'), 'zeigt die Vorschau');
  t.isTrue(
    !Directory('${dir.path}/out').existsSync() &&
        File('${dir.path}/k.md').readAsStringSync() == _concept(_rows),
    'ohne --apply wird nichts geschrieben',
  );
  File('${dir.path}/s.md').writeAsStringSync('# leer\n');
  t.eq(run([]).exitCode, 1, 'ohne Meilenstein-Tabelle Abbruch statt Raten');
  File('${dir.path}/s.md').writeAsStringSync(_status);
  final applied = run(['--apply']);
  t.eq(applied.exitCode, 0, 'concept_archive --apply: Exit 0');
  t.isTrue(
    File('${dir.path}/out/README.md')
        .readAsStringSync()
        .contains('| 3 | K3–K4, K8 |'),
    'README nennt Bereiche statt Anfang–Ende',
  );
  final m5 = File('${dir.path}/out/M5.md');
  t.isTrue(
    m5.existsSync() && m5.readAsStringSync().contains('| K3 |'),
    'M5-Archiv enthält K3',
  );
  final after = File('${dir.path}/k.md').readAsStringSync();
  final second = run(['--apply']);
  t.isTrue(
    '${second.stdout}'.contains('Archiviere 0 Einträge') &&
        File('${dir.path}/k.md').readAsStringSync() == after,
    'zweiter --apply ist ein No-op',
  );
  dir.deleteSync(recursive: true);
}
