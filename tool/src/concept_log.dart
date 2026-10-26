// Änderungsprotokoll des Konzepts (WP147): Tabelle lesen, bestätigte Einträge
// in Meilenstein-Archive verschieben und das Konzept gegen STATUS und ADRs
// prüfen. Reine Logik auf Text; die Aufrufer sind `tool/concept_archive.dart`
// und `tool/check_concept.dart`.
//
// Meilenstein-Regel (für `docs/concept-changelog/M<n>.md`):
//  1. Maßgeblich ist die erste Paketnummer `WP<n>` in der Spalte „Grund“; die
//     Zuordnung Paket → Meilenstein liest das Werkzeug aus der Tabelle
//     „Meilensteine“ in `docs/work-packages/STATUS.md` (Spalte „Pakete“). Das
//     ist die einzige Stelle, an der der Orchestrator Meilensteine pflegt, und
//     der Grund nennt das Paket, das die Abweichung ausgelöst hat.
//  2. Liegt die Nummer in mehreren Zeilen (z. B. WP76 in M4 und M5 für die
//     Teilpakete 76b–d), gewinnt die spätere Zeile; liegt sie in keiner, gilt
//     der Meilenstein des nächstkleineren aufgeführten Pakets (neue Pakete
//     landen so im laufenden Meilenstein), davor der der ersten Zeile.
//     Steht in einer Zeile mehr als ein Meilenstein („M0 …, M1 …“), gilt der
//     letzte.
//  3. Ohne Paketnummer im Grund (Gerätetest, Entscheidung des Maintainers)
//     gilt der Meilenstein des nächsten Eintrags mit Paketnummer, wenn dieser
//     dasselbe Datum trägt, sonst der des vorigen (die Tabelle ist
//     chronologisch); ein führender Eintrag nimmt den des nächsten.
//
//  Begründung (geprüft an STATUS.md und der Tabelle im Konzept): Die Zuordnung
//  nach Paketnummer trägt. Die Tabelle „Meilensteine“ und „M5 im Detail“ in
//  STATUS.md nennen für M5 dieselben Pakete (WP76b–d, WP79, WP81–WP98,
//  WP102–WP110; WP76a steht nur im Detail, WP76 trifft die M5-Zeile), und
//  alle Einträge ab K57 mit Paketnummer landen in M5 (K82/WP99 in M6, bleibt
//  als offen im Konzept). Eine andere Paketliste ergäbe nichts Neues. Schwach
//  war nur Regel 3: „vom Vorgänger erben“ ordnete die Entscheidungen K48–K56
//  vom 2026-10-18 (M5-Start, K48 „M5 nur Android“, K56 gehört zu WP83) M4 zu,
//  obwohl K57 (WP91, M5) am selben Tag steht. Der Gleichtag-Vorrang ist die
//  einfache, am Datum belegbare Korrektur; ohne Datum zu raten.
//  Bleibt kein Meilenstein bestimmbar (keine Zeilen in STATUS), bricht das
//  Werkzeug ab statt zu raten.

/// Ein Eintrag des Änderungsprotokolls.
typedef KEntry = ({
  int nr,
  String date,
  String ground,
  String status,
  String line,
});

/// Abschnittsüberschrift des Änderungsprotokolls im Konzept.
const logHeading = '## Änderungsprotokoll';

/// Verweis im Konzept auf das Archiv (Marker für Idempotenz).
const archiveDir = 'docs/concept-changelog';

final _rowStart = RegExp(r'^\| K(\d+) \| ');

/// Liest die K-Zeilen aus [lines] (ganze Zeilen der Tabelle).
///
/// Zellen werden an ` | ` getrennt (nicht an `|`): eine Zeile darf ein
/// einzelnes `|` in Backticks enthalten (K56). Status ist die letzte, Grund
/// die vorletzte Zelle.
List<KEntry> parseEntries(Iterable<String> lines) {
  final out = <KEntry>[];
  for (final l in lines) {
    final m = _rowStart.firstMatch(l);
    if (m == null) continue;
    final cells = l.trim().replaceAll(RegExp(r'^\||\|$'), '').split(' | ');
    if (cells.length < 6) continue;
    out.add((
      nr: int.parse(m[1]!),
      date: cells[1].trim(),
      ground: cells[cells.length - 2].trim(),
      status: cells.last.trim(),
      line: l,
    ));
  }
  return out;
}

/// Art des Status: `bestätigt`, `offen`, `zurückgestellt` oder `gemischt`
/// (z. B. „(1) bestätigt …; (2)–(4) offen“).
String statusKind(String status) {
  final s = status.trim();
  for (final k in const ['bestätigt', 'offen', 'zurückgestellt']) {
    if (s.startsWith(k)) return k;
  }
  return 'gemischt';
}

/// Ob der Eintrag vollständig bestätigt ist und ins Archiv wandert: Status
/// beginnt mit „bestätigt“ und nennt (abgesehen von der Vorgeschichte hinter
/// „vorher:“) nichts Offenes, z. B. „Umfang offen“.
bool isArchivable(String status) {
  if (statusKind(status) != 'bestätigt') return false;
  final now = status.split('vorher:').first;
  return !RegExp(r'\boffen\b').hasMatch(now);
}

/// Zuordnung Paketnummer → Meilensteinzahl aus STATUS.md ([statusText]).
final class MilestoneMap {
  MilestoneMap._(this._ranges);

  /// Liest die Tabelle „Meilensteine“; leer, wenn sie fehlt.
  factory MilestoneMap.fromStatus(String statusText) {
    final ranges = <({int lo, int hi, int m})>[];
    final lines = statusText.split('\n');
    final start = lines.indexWhere((l) => l.startsWith('## Meilensteine'));
    if (start >= 0) {
      for (var i = start + 1; i < lines.length; i++) {
        final l = lines[i];
        if (l.startsWith('## ')) break;
        if (!l.startsWith('| M')) continue;
        final cells = l.split('|').map((c) => c.trim()).toList();
        if (cells.length < 4) continue;
        final ms = RegExp(r'\bM(\d+)\b').allMatches(cells[1]).toList();
        if (ms.isEmpty) continue;
        final m = int.parse(ms.last[1]!);
        for (final t in RegExp(
          r'WP(\d+)[a-z]?(?:–WP(\d+)[a-z]?)?',
        ).allMatches(cells[2])) {
          final lo = int.parse(t[1]!);
          ranges.add((lo: lo, hi: t[2] == null ? lo : int.parse(t[2]!), m: m));
        }
      }
    }
    return MilestoneMap._(ranges);
  }

  final List<({int lo, int hi, int m})> _ranges;

  /// Ob die Tabelle gelesen werden konnte.
  bool get isEmpty => _ranges.isEmpty;

  /// Meilenstein von Paket [wp] nach Regel 2 im Kopf dieser Datei.
  int of(int wp) {
    for (final r in _ranges.reversed) {
      if (wp >= r.lo && wp <= r.hi) return r.m;
    }
    ({int lo, int hi, int m})? best;
    for (final r in _ranges) {
      if (r.hi <= wp && (best == null || r.hi >= best.hi)) best = r;
    }
    return (best ?? _ranges.first).m;
  }
}

/// Meilenstein je Eintrag (Regel 1 bis 3); `null`-Einträge gibt es nicht.
Map<int, int> assignMilestones(List<KEntry> entries, MilestoneMap map) {
  final byWp = <int, int?>{};
  for (final e in entries) {
    final wp = RegExp(r'WP(\d+)').firstMatch(e.ground);
    byWp[e.nr] = wp == null ? null : map.of(int.parse(wp[1]!));
  }
  final out = <int, int>{};
  int? last;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    var m = byWp[e.nr];
    if (m == null) {
      // Gleichtag-Vorrang: nächster Eintrag mit Paketnummer am selben Datum.
      for (var j = i + 1; j < entries.length; j++) {
        if (entries[j].date != e.date) break;
        final n = byWp[entries[j].nr];
        if (n != null) {
          m = n;
          break;
        }
      }
    }
    last = m ?? last;
    if (last != null) out[e.nr] = last;
  }
  int? next;
  for (final e in entries.reversed) {
    next = byWp[e.nr] ?? out[e.nr] ?? next;
    out.putIfAbsent(e.nr, () => next!);
  }
  return out;
}

/// Kopf einer Archivdatei.
String archiveHead(int m) =>
    '# Änderungsprotokoll des Konzepts: Meilenstein M$m (archiviert)\n\n'
    '<!-- ERZEUGT von tool/concept_archive.dart. Einträge nicht von Hand '
    'verschieben. -->\n\n'
    'Bestätigte Einträge des Änderungsprotokolls im Gesamtkonzept, die dem '
    'Meilenstein M$m zugeordnet sind (Regel: Kopf von '
    '`tool/src/concept_log.dart`). Offene und zurückgestellte Einträge stehen '
    'im Konzept selbst; Übersicht: [README](README.md).\n\n'
    '| Nr. | Datum | Abschnitt | Änderung | Grund | Status |\n'
    '| --- | --- | --- | --- | --- | --- |\n';

/// Neuer Inhalt der Archivdatei für [m]: bestehende Zeilen aus [existing]
/// plus [add], nach K-Nummer sortiert, ohne Doppelte (idempotent).
String renderArchive(int m, String existing, List<KEntry> add) {
  final byNr = <int, String>{
    for (final e in parseEntries(existing.split('\n'))) e.nr: e.line,
    for (final e in add) e.nr: e.line,
  };
  final nrs = byNr.keys.toList()..sort();
  return '${archiveHead(m)}${[for (final n in nrs) byNr[n]].join('\n')}\n';
}

/// Index des Archivs: Datei → K-Nummern (aus den Dateiinhalten [files]).
String renderIndex(Map<String, String> files) {
  final names = files.keys.toList()..sort((a, b) => _num(a).compareTo(_num(b)));
  final b = StringBuffer()
    ..writeln('# Archiv des Änderungsprotokolls')
    ..writeln()
    ..writeln(
      '<!-- ERZEUGT von tool/concept_archive.dart. Nicht von Hand ändern. '
      '-->',
    )
    ..writeln()
    ..writeln(
      'Bestätigte Einträge (K-Nummern) aus dem Gesamtkonzept, je Meilenstein '
      'eine Datei. Zuordnung: Kopf von `tool/src/concept_log.dart`. Offene '
      'und zurückgestellte Einträge bleiben im Konzept.',
    )
    ..writeln()
    ..writeln('| Meilenstein | Einträge | K-Nummern |')
    ..writeln('| --- | --- | --- |');
  for (final n in names) {
    final nrs = [for (final e in parseEntries(files[n]!.split('\n'))) e.nr]
      ..sort();
    b.writeln(
      '| [$n]($n) | ${nrs.length} | ${nrs.isEmpty ? '–' : _ranges(nrs)} |',
    );
  }
  return b.toString();
}

/// Sortierte Nummern als Bereiche: `K11, K14, K16–K19`.
String _ranges(List<int> nrs) {
  final parts = <String>[];
  for (var i = 0; i < nrs.length;) {
    var j = i;
    while (j + 1 < nrs.length && nrs[j + 1] == nrs[j] + 1) {
      j++;
    }
    parts.add(j == i ? 'K${nrs[i]}' : 'K${nrs[i]}–K${nrs[j]}');
    i = j + 1;
  }
  return parts.join(', ');
}

int _num(String file) =>
    int.tryParse(RegExp(r'\d+').firstMatch(file)?[0] ?? '') ?? 0;

/// Ergebnis des Archivierens.
typedef ArchivePlan = ({
  String concept,
  Map<int, List<KEntry>> moved,
  List<int> kept,
});

/// Entfernt die archivierbaren Zeilen aus [concept] und fügt den Verweis auf
/// das Archiv ein. Gibt die verschobenen Einträge je Meilenstein zurück.
ArchivePlan planArchive(String concept, MilestoneMap map) {
  final lines = concept.split('\n');
  final start = lines.indexWhere((l) => l.startsWith(logHeading));
  if (start < 0) throw const FormatException('Abschnitt fehlt: $logHeading');
  final entries = parseEntries(lines.skip(start));
  final ms = assignMilestones(entries, map);
  final moved = <int, List<KEntry>>{};
  final drop = <String>{};
  final kept = <int>[];
  for (final e in entries) {
    if (isArchivable(e.status)) {
      moved.putIfAbsent(ms[e.nr]!, () => []).add(e);
      drop.add(e.line);
    } else {
      kept.add(e.nr);
    }
  }
  final out = <String>[];
  var pointer = lines.skip(start).any((l) => l.contains('$archiveDir/'));
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (i > start && drop.contains(l)) continue;
    out.add(l);
    if (i > start && !pointer && l.startsWith('Abweichungen, die sich')) {
      out
        ..add('')
        ..add(
          'Bestätigte Einträge stehen im Archiv `$archiveDir/` (eine Datei je '
          'Meilenstein, Übersicht in der README dort); hier bleiben die '
          'offenen, zurückgestellten und teilweise bestätigten Einträge.',
        );
      pointer = true;
    }
  }
  return (concept: out.join('\n'), moved: moved, kept: kept);
}

/// K-Status je Nummer aus Konzept- und Archivtexten.
Map<int, String> statusByNr(Iterable<String> texts) => {
  for (final t in texts)
    for (final e in parseEntries(t.split('\n'))) e.nr: e.status,
};

/// Bestätigte K-Nummern (Status beginnt mit „bestätigt“).
Iterable<int> confirmedNrs(Map<int, String> status) => [
  for (final e in status.entries)
    if (statusKind(e.value) == 'bestätigt') e.key,
]..sort();

/// Zahlen `Knn` in Klammern des Konzepttexts [body] und als Wort in den ADRs.
Set<int> referencedNrs(String body, Iterable<String> adrs) {
  final out = <int>{};
  for (final p in RegExp(r'\([^()\n]*\)').allMatches(body)) {
    for (final k in RegExp(r'\bK(\d+)\b').allMatches(p[0]!)) {
      out.add(int.parse(k[1]!));
    }
  }
  for (final a in adrs) {
    for (final k in RegExp(r'\bK(\d+)\b').allMatches(a)) {
      out.add(int.parse(k[1]!));
    }
  }
  return out;
}

/// Text des Konzepts vor dem Änderungsprotokoll.
String conceptBody(String concept) {
  final i = concept.indexOf('\n$logHeading');
  return i < 0 ? concept : concept.substring(0, i);
}

/// K-Status, die STATUS.md nennt: `K59 bestätigt`, `K74, K77 bestätigt`,
/// `K66/K68 bestätigt`, `K81 offen`, `K5 zurückgestellt` (Nummer → alle
/// Nennungen mit Zeilennummer, in Dateireihenfolge).
Map<int, List<({String word, int line})>> statusMentions(String statusText) {
  final out = <int, List<({String word, int line})>>{};
  final lines = statusText.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final m in RegExp(
      r'((?:K\d+\s*[,/]\s*)*K\d+)\s+(bestätigt|offen|zurückgestellt)\b',
    ).allMatches(lines[i])) {
      for (final k in RegExp(r'K(\d+)').allMatches(m[1]!)) {
        out.putIfAbsent(int.parse(k[1]!), () => []).add((
          word: m[2]!,
          line: i + 1,
        ));
      }
    }
  }
  return out;
}
