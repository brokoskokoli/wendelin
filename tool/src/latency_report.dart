// Auswertung der Logzeilen `Wendelin/voice: latency k=v ...` (WP120).
//
// Rein (ohne Ein-/Ausgabe), damit der Selbsttest sie prüft. Aufruf:
// `dart run tool/latency_report.dart [log.txt]` (ohne Datei: stdin).

/// Eine Logzeile `latency` als Zahlenfelder, sonst `null`.
Map<String, int>? parseLatencyLine(String line) {
  const marker = 'Wendelin/voice: latency ';
  final i = line.indexOf(marker);
  if (i < 0) return null;
  final out = <String, int>{};
  for (final part in line.substring(i + marker.length).split(' ')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final v = int.tryParse(part.substring(eq + 1));
    if (v != null) out[part.substring(0, eq)] = v;
  }
  return out.isEmpty ? null : out;
}

/// Zusätzliche Abschnitte aus den Rohfeldern (Differenzen).
Map<String, int> derivedSections(Map<String, int> f) {
  final out = Map<String, int>.of(f)
    ..removeWhere((k, _) => k == 'calls' || k == 'tools' || k == 'sentences');
  void diff(String name, String a, String b) {
    final x = f[a];
    final y = f[b];
    if (x != null && y != null) out[name] = x - y;
  }

  diff('audio_first-stt', 'audio_first', 'stt');
  diff('m1_done-m1_req', 'm1_done', 'm1_req');
  return out;
}

/// Nearest-Rank-Perzentil [p] (0 bis 100) der sortierten [values].
int percentile(List<int> values, int p) {
  final s = List<int>.of(values)..sort();
  final rank = (p / 100 * s.length).ceil().clamp(1, s.length);
  return s[rank - 1];
}

/// Tabelle (Abschnitt, n, p50, p90) über alle Latenzzeilen in [log].
String latencyReport(String log) {
  final bySection = <String, List<int>>{};
  var requests = 0;
  for (final line in log.split('\n')) {
    final f = parseLatencyLine(line);
    if (f == null) continue;
    requests++;
    derivedSections(f)
        .forEach((k, v) => bySection.putIfAbsent(k, () => []).add(v));
  }
  if (requests == 0) return 'Keine Zeilen `Wendelin/voice: latency` gefunden.';
  final keys = bySection.keys.toList()..sort(_byName);
  final b = StringBuffer('Anfragen: $requests (Zeiten in ms)\n')
    ..writeln(
      '${'Abschnitt'.padRight(18)}${'n'.padLeft(4)}'
      '${'p50'.padLeft(8)}${'p90'.padLeft(8)}',
    );
  for (final k in keys) {
    final v = bySection[k]!;
    b.writeln(
      '${k.padRight(18)}${'${v.length}'.padLeft(4)}'
      '${'${percentile(v, 50)}'.padLeft(8)}${'${percentile(v, 90)}'.padLeft(8)}',
    );
  }
  return b.toString().trimRight();
}

int _byName(String a, String b) {
  int num(String s) =>
      int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '') ?? 0;
  final c = num(a).compareTo(num(b));
  return c != 0 ? c : a.compareTo(b);
}
