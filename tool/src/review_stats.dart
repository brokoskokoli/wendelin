// Auswertung der Urteilsdateien des Reviewers (WP110, Format in
// docs/work-packages/REVIEW.md): `../james-wt/reviews/<wp>-review[N].md`.
import 'dart:io';

/// Kategorien der Befunde (Schlüssel der Coder-Checkliste plus `sonstiges`).
const reviewCategories = [
  'bestaetigung',
  'fail-closed',
  'dispose',
  'negativtest',
  'texte',
  'doku',
  'berechtigung',
  'sonstiges',
];

/// Kopf einer Urteilsdatei.
final class ReviewHeader {
  /// Erstellt den Kopf.
  const ReviewHeader({
    required this.verdict,
    required this.round,
    required this.mutations,
    required this.survived,
    required this.findings,
  });

  /// `FREIGABE` oder `NACHBESSERN`.
  final String verdict;

  /// Runde (1 = erstes Review).
  final int round;

  /// Getestete und überlebende Mutationen.
  final int mutations, survived;

  /// Befunde je Kategorie.
  final Map<String, int> findings;

  /// Erstes Review ohne Nachbesserung.
  bool get cleanFirst => round == 1 && verdict == 'FREIGABE';
}

/// Liest den Kopf aus [text]; `null`, wenn er fehlt oder unvollständig ist.
ReviewHeader? parseReview(String text) {
  final kv = <String, String>{};
  for (final line in text.split('\n').take(30)) {
    final m = RegExp(r'^(URTEIL|RUNDE|MUTATIONEN|BEFUNDE):\s*(.*?)\s*$')
        .firstMatch(line);
    if (m != null) kv.putIfAbsent(m[1]!, () => m[2]!);
  }
  final verdict = kv['URTEIL'];
  final round = int.tryParse(kv['RUNDE'] ?? '');
  final mut = RegExp(r'^(\d+)/(\d+)$').firstMatch(kv['MUTATIONEN'] ?? '');
  if (verdict == null ||
      !const {'FREIGABE', 'NACHBESSERN'}.contains(verdict) ||
      round == null ||
      mut == null ||
      kv['BEFUNDE'] == null) {
    return null;
  }
  final findings = <String, int>{};
  for (final part in kv['BEFUNDE']!.split(RegExp(r'\s+'))) {
    final m = RegExp(r'^([a-z-]+)=(\d+)$').firstMatch(part);
    if (m == null) return null;
    findings[m[1]!] = int.parse(m[2]!);
  }
  return ReviewHeader(
    verdict: verdict,
    round: round,
    mutations: int.parse(mut[1]!),
    survived: int.parse(mut[2]!),
    findings: findings,
  );
}

/// Zusammenfassung über [files] (Name → Inhalt).
String summarizeReviews(Map<String, String> files) {
  final ok = <String, ReviewHeader>{};
  final bad = <String>[];
  for (final MapEntry(:key, :value) in files.entries) {
    final h = parseReview(value);
    if (h == null) {
      bad.add(key);
    } else {
      ok[key] = h;
    }
  }
  final first = ok.values.where((h) => h.round == 1).toList();
  final clean = first.where((h) => h.cleanFirst).length;
  final byCat = {for (final c in reviewCategories) c: 0};
  var mut = 0, surv = 0;
  for (final h in ok.values) {
    mut += h.mutations;
    surv += h.survived;
    for (final MapEntry(:key, :value) in h.findings.entries) {
      byCat[key] = (byCat[key] ?? 0) + value;
    }
  }
  final pct = first.isEmpty ? '-' : '${(clean * 100 / first.length).round()} %';
  return [
    'Urteilsdateien: ${ok.length} gültig${bad.isEmpty ? '' : ', ungültig: ${bad.join(', ')}'}',
    'Beim ersten Review sauber: $clean von ${first.length} ($pct)',
    'Befunde je Kategorie: ${byCat.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    'Mutationen: $mut getestet, $surv überlebt',
  ].join('\n');
}

/// Liest alle `*-review*.md` aus [dir].
Map<String, String> readReviews(String dir) => {
  for (final f in Directory(dir).listSync().whereType<File>())
    if (RegExp(r'-review\d*\.md$').hasMatch(f.path))
      f.uri.pathSegments.last: f.readAsStringSync(),
};

/// Standardordner der Urteile: `<Hauptcheckout>/../james-wt/reviews`.
///
/// Der Hauptcheckout ist das Elternverzeichnis des gemeinsamen Git-Ordners
/// (`git rev-parse --git-common-dir`), das gilt im Hauptcheckout wie in jedem
/// Worktree. [git] liefert die Ausgabe oder `null` bei einem Fehler; außerhalb
/// eines Repos gilt `../james-wt/reviews` relativ zum Arbeitsverzeichnis.
String defaultReviewsDir(String? Function(List<String> args) git) {
  final common = git([
    'rev-parse',
    '--path-format=absolute',
    '--git-common-dir',
  ]);
  if (common == null || common.isEmpty) return '../james-wt/reviews';
  final trimmed = common.endsWith('/')
      ? common.substring(0, common.length - 1)
      : common;
  final gitDir = trimmed.lastIndexOf('/');
  if (gitDir <= 0) return '../james-wt/reviews';
  final main = trimmed.substring(0, gitDir);
  final parent = main.lastIndexOf('/');
  if (parent < 0) return '../james-wt/reviews';
  return '${main.substring(0, parent)}/james-wt/reviews';
}
