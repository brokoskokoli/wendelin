// Selbsttests zu WP110: Text-Check, Prüfumfang (--only/--globals) und die
// Struktur von .github/workflows/gate.yml (Doku-Läufe verkürzt).
import 'dart:io';

import 'gate_changed.dart';
import 'review_stats.dart';
import 'self_check.dart';
import 'text_scan.dart';

void ciChecks(SelfCheck t) {
  _textChecks(t);
  _scopeChecks(t);
  _workflowChecks(t);
  _reviewChecks(t);
}

void _textChecks(SelfCheck t) {
  t.group('check_texts');
  final dir = Directory.systemTemp.createTempSync('texts_');
  try {
    File('${dir.path}/a.dart').writeAsStringSync(
      "const a = 'Das ist ein Test';\n"
      "x(yes: 'Ja, löschen', no: 'Nein, behalten');\n"
      "showHint(context, 'Die Datei ist weg');\n"
      "final b = 'ok';\n"
      "final c = 'Abmelden';\n"
      "final d = 'Details';\n"
      "final e = 'save';\n"
      "// 'Das steht im Kommentar und ist fein'\n",
    );
    final found = scanTexts(dir.path);
    t.eq(
      found.length,
      5,
      'Scan erkennt 5 feste Texte, nicht Bezeichner/Kommentar',
    );
    final path = '${dir.path}/a.dart';
    t.eq(
      compareTexts(found, {path: 5}),
      <String>[],
      'Bestand in der Allowlist: grün',
    );
    final neu = compareTexts(found, {path: 4});
    t.isTrue(
      neu.length == 1 && neu.first.contains('feste Texte (erlaubt 4)'),
      'neuer fester Text über der Allowlist: rot',
    );
    t.isTrue(
      compareTexts(found, const {}).isNotEmpty,
      'Datei ohne Eintrag: rot',
    );
    final weniger = compareTexts(found, {path: 7});
    t.isTrue(
      weniger.length == 1 && weniger.first.contains('auf 5 senken'),
      'Allowlist zu hoch: rot (nur abbauen)',
    );
    t.isTrue(
      compareTexts(const [], {'x.dart': 1}).first.contains('entfernen'),
      'Eintrag ohne Treffer: entfernen',
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void _scopeChecks(SelfCheck t) {
  t.group('gate --only/--globals');
  final only = explicitScope(['--only', 'wendelin_core', '--shard=1/2']);
  t.eq(only.targets, {'wendelin_core'}, '--only: genau dieses Ziel');
  t.isTrue(
    !only.globalChecks && !only.tooling,
    '--only: keine globalen Prüfungen, keine Selbsttests',
  );
  final pos = explicitScope(['wendelin_core']);
  t.isTrue(
    pos.globalChecks && pos.tooling,
    'ohne --only bleiben die globalen Prüfungen',
  );
  final g = explicitScope(['--globals']);
  t.isTrue(
    g.targets!.isEmpty && g.globalChecks && g.tooling,
    '--globals: keine Pakete, nur globale Prüfungen',
  );
  t.eq(shardFlags((index: 2, total: 2)), [
    '--total-shards=2',
    '--shard-index=1',
  ], 'Shard 2/2: Index 1 von 2');
  t.eq(shardFlags(null), <String>[], 'ohne Shard keine Argumente');
  final all = explicitScope([]);
  t.isTrue(all.targets == null && all.globalChecks, 'ohne Angabe: alles');
}

/// Gerüst von gate.yml: Jobblöcke nach Namen.
Map<String, String> _jobs(String yml) {
  final out = <String, String>{};
  String? name;
  final buf = StringBuffer();
  var inJobs = false;
  for (final line in yml.split('\n')) {
    if (line == 'jobs:') {
      inJobs = true;
      continue;
    }
    if (!inJobs) continue;
    final m = RegExp(r'^  ([a-z][a-z0-9-]*):\s*$').firstMatch(line);
    if (m != null) {
      if (name != null) out[name] = buf.toString();
      name = m[1];
      buf.clear();
    } else {
      buf.writeln(line);
    }
  }
  if (name != null) out[name] = buf.toString();
  return out;
}

/// Doku-Läufe (WP110): Nur `docs-only` läuft bei reinen Doku-Änderungen, alle
/// anderen Jobs (außer Identität und Umfang) hängen an `docs_only != 'true'`.
void _workflowChecks(SelfCheck t) {
  t.group('gate.yml (verkürzte Doku-Läufe)');
  final f = File('.github/workflows/gate.yml');
  if (!f.existsSync()) {
    t.isTrue(false, 'gate.yml fehlt');
    return;
  }
  final jobs = _jobs(f.readAsStringSync());
  const free = {'commit-identity', 'scope', 'docs-only'};
  for (final MapEntry(:key, :value) in jobs.entries) {
    if (free.contains(key)) continue;
    t.isTrue(
      value.contains("if: needs.scope.outputs.docs_only != 'true'") ||
          value.contains("needs.scope.outputs.docs_only != 'true' &&"),
      'Job $key überspringt bei reinen Doku-Änderungen',
    );
    t.isTrue(
      RegExp(r'needs: (scope|\[scope,)').hasMatch(value),
      'Job $key hängt an scope',
    );
  }
  final docs = jobs['docs-only'] ?? '';
  t.isTrue(
    docs.contains("docs_only == 'true'"),
    'docs-only läuft nur bei Doku',
  );
  t.isTrue(
    docs.contains('tool/check_docs.dart') &&
        !docs.contains('gate.dart') &&
        !docs.contains('flutter test'),
    'docs-only führt nur check_docs aus',
  );
  t.isTrue(
    (jobs['scope'] ?? '').contains('tool/ci_scope.sh --ci'),
    'scope nutzt ci_scope.sh',
  );
  final pk = jobs['packages'] ?? '';
  t.isTrue(
    pk.contains('tool/gate.dart --only '),
    'Matrix nutzt gate.dart --only',
  );
  t.isTrue(
    (jobs['global-checks'] ?? '').contains('gate.dart --globals'),
    'globale Prüfungen im eigenen Job',
  );
  t.isTrue(
    (jobs['scope'] ?? '').contains('"wendelin_integrations"') &&
        (jobs['scope'] ?? '').contains('shards: 2'),
    'wendelin_integrations in 2 Shards',
  );
  t.isTrue(
    (jobs['pkg-coverage'] ?? '').contains('check_pkg_coverage.dart'),
    'Shard-Abdeckung wird zusammengeführt',
  );
}

void _reviewChecks(SelfCheck t) {
  t.group('review_stats');
  const ok1 =
      'URTEIL: FREIGABE\nRUNDE: 1\nMUTATIONEN: 5/0\nBEFUNDE: texte=0 doku=1\n\nText';
  const bad1 =
      'URTEIL: NACHBESSERN\nRUNDE: 1\nMUTATIONEN: 6/2\nBEFUNDE: fail-closed=1 negativtest=2\n';
  const re2 =
      'URTEIL: FREIGABE\nRUNDE: 2\nMUTATIONEN: 3/0\nBEFUNDE: sonstiges=0\n';
  final h = parseReview(bad1)!;
  t.isTrue(
    !h.cleanFirst && h.survived == 2 && h.findings['negativtest'] == 2,
    'Kopf gelesen',
  );
  t.isTrue(parseReview(ok1)!.cleanFirst, 'Runde 1 mit FREIGABE ist sauber');
  t.isTrue(!parseReview(re2)!.cleanFirst, 'Re-Review zählt nicht als sauber');
  t.eq(
    parseReview(
      'URTEIL: VIELLEICHT\nRUNDE: 1\nMUTATIONEN: 1/0\nBEFUNDE: texte=0',
    ),
    null,
    'unbekanntes Urteil ungültig',
  );
  t.eq(
    parseReview(
      'URTEIL: FREIGABE\nRUNDE: 1\nMUTATIONEN: viele\nBEFUNDE: texte=0',
    ),
    null,
    'Mutationen müssen n/m sein',
  );
  t.eq(parseReview('Freitext ohne Kopf'), null, 'ohne Kopf ungültig');
  final out = summarizeReviews({
    'a-review.md': ok1,
    'b-review.md': bad1,
    'b-review2.md': re2,
    'c-review.md': 'kaputt',
  });
  t.isTrue(out.contains('1 von 2 (50 %)'), 'Quote sauber: 1 von 2 ($out)');
  t.isTrue(out.contains('ungültig: c-review.md'), 'ungültige Datei genannt');
  t.isTrue(
    out.contains('Mutationen: 14 getestet, 2 überlebt'),
    'Mutationsbilanz',
  );
}
