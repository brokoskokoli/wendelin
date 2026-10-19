// Selbsttests von tool/merge_wp.sh in temporären Git-Repos.
import 'dart:io';

import 'cleanup_self_test.dart';
import 'git_guards_self_test.dart';
import 'ratchet_self_test.dart';
import 'self_check.dart';

const _good = 'brokoskokoli';
const _goodMail = '16724498+brokoskokoli@users.noreply.github.com';
const _oldAuthor = {
  'GIT_AUTHOR_NAME': 'Alt Name',
  'GIT_AUTHOR_EMAIL': 'alt@example.org',
};
const _oldCommitter = {
  'GIT_COMMITTER_NAME': 'Alt Name',
  'GIT_COMMITTER_EMAIL': 'alt@example.org',
};
const _trailer =
    'Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>';

/// CI-Ersatz: ein grüner gate-Lauf auf genau dem Branch-SHA.
const ciGreen =
    r'printf "2026-01-01T00:00:00Z\t%s\t%s\tcompleted\tsuccess\n" "$SHA" "$BRANCH"';

/// CI-Ersatz mit festen Laufzeilen (`<createdAt> <sha> <branch> <status> <conclusion>`,
/// Tab-getrennt); `SHA`/`BRANCH` stehen für den Branch.
String ciRuns(List<String> rows) =>
    "printf '%s\\n' ${rows.map((r) => "'${r.replaceAll(' ', '\t')}'").join(' ')}";

/// Temporäres Repo mit Hilfen zum Anlegen von Branches und zum Aufruf des Skripts.
final class _Repo {
  _Repo(this.dir, this.script)
    : env = {
        'GIT_CONFIG_GLOBAL': '/dev/null',
        'GIT_CONFIG_SYSTEM': '/dev/null',
        'GIT_AUTHOR_NAME': _good,
        'GIT_AUTHOR_EMAIL': _goodMail,
        'GIT_COMMITTER_NAME': _good,
        'GIT_COMMITTER_EMAIL': _goodMail,
        'MERGE_WP_GATE': 'true',
        'MERGE_WP_CI': ciGreen,
        'MERGE_WP_CLEANUP': File('tool/cleanup_wt.sh').absolute.path,
      };

  final Directory dir;
  final String script;
  final Map<String, String> env;

  String git(List<String> a, {Map<String, String> extra = const {}}) {
    final r = Process.runSync(
      'git',
      a,
      workingDirectory: dir.path,
      environment: {...env, ...extra},
    );
    if (r.exitCode != 0) throw StateError('git $a: ${r.stderr}');
    return (r.stdout as String).trim();
  }

  ProcessResult merge(List<String> a, {Map<String, String> extra = const {}}) =>
      Process.runSync(
        'bash',
        [script, ...a],
        workingDirectory: dir.path,
        environment: {...env, ...extra},
      );

  void commit(
    String file,
    String text,
    String msg, {
    Map<String, String> extra = const {},
  }) {
    File('${dir.path}/$file').writeAsStringSync(text);
    git(['add', file]);
    git(['commit', '-q', '-m', msg], extra: extra);
  }

  String head() => git(['rev-parse', 'HEAD']);

  bool hasBranch(String b) =>
      Process.runSync(
        'git',
        ['rev-parse', '--verify', '-q', 'refs/heads/$b'],
        workingDirectory: dir.path,
        environment: env,
      ).exitCode ==
      0;

  void branch(
    String name,
    String file,
    String msg, {
    Map<String, String> extra = const {},
  }) {
    git(['checkout', '-q', '-b', name, 'main']);
    commit(file, '$name\n', msg, extra: extra);
    git(['checkout', '-q', 'main']);
  }
}

/// Selbsttests der Git-Skripte: merge_wp.sh und die Leitplanken (WP109).
void mergeWpChecks(SelfCheck t) {
  ratchetChecks(t);
  gitGuardsChecks(t);
  cleanupChecks(t);
  t.group('merge_wp.sh');
  final dir = Directory.systemTemp.createTempSync('merge_wp_');
  try {
    final r = _Repo(dir, File('tool/merge_wp.sh').absolute.path);
    r.git(['init', '-q', '-b', 'main']);
    Directory('${dir.path}/tool').createSync();
    File('tool/regen_generated.sh')
        .copySync('${dir.path}/tool/regen_generated.sh');
    r.commit('a.txt', 'a\n', 'init');
    _rejections(t, r);
    _ciChecks(t, r);
    _successes(t, r);
    _conflicts(t, r);
    _generators(t, r);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void _rejections(SelfCheck t, _Repo r) {
  final start = r.head();
  r.branch('wrong-id', 'b.txt', 'x', extra: _oldAuthor);
  var res = r.merge(['wrong-id']);
  t.isTrue(res.exitCode != 0, 'falsche Identität → Abbruch');
  t.eq(r.head(), start, 'falsche Identität: main unverändert');

  r.branch(
    'sess',
    'c.txt',
    'x\n\nClaude-Session: https://claude.ai/code/session_x',
  );
  res = r.merge(['sess']);
  t.isTrue(res.exitCode != 0, 'Session-Zeile → Abbruch');
  t.eq(r.head(), start, 'Session-Zeile: main unverändert');

  res = r.merge(['sess', '--squash', '-m', 'ok\nClaude-Session: https://x']);
  t.isTrue(res.exitCode != 0, 'Session-Zeile in -m → Abbruch');
  t.eq(r.head(), start, 'Session-Zeile in -m: main unverändert');

  res = r.merge(['wrong-id', '--squash', '--dry-run']);
  t.isTrue(
    res.exitCode == 0 && r.head() == start && r.hasBranch('wrong-id'),
    'dry-run verändert nichts',
  );

  // Nur der Committer ist falsch (Autor stimmt).
  r.branch('wrong-committer', 'f.txt', 'x', extra: _oldCommitter);
  res = r.merge(['wrong-committer']);
  t.isTrue(res.exitCode != 0, 'falsche Committer-Identität → Abbruch');
  t.eq(r.head(), start, 'falscher Committer: main unverändert');

  // Unsauberer Baum.
  File('${r.dir.path}/a.txt').writeAsStringSync('schmutzig\n');
  res = r.merge(['sess', '--squash', '-m', 'ok']);
  t.isTrue(res.exitCode != 0, 'unsauberer Baum → Abbruch');
  t.isTrue(
    '${res.stderr}'.contains('nicht sauber') && r.hasBranch('sess'),
    'unsauberer Baum: Meldung, Branch bleibt',
  );
  t.eq(r.head(), start, 'unsauberer Baum: main unverändert');
  r.git(['checkout', '--', 'a.txt']);

  // Ergebnisnachricht allein: nur die Betreffzeile des letzten Commits (ohne
  // -m) ist die spätere Nachricht und trägt hier die Session-Zeile.
  r.branch(
    'subj',
    'g2.txt',
    'Claude-Session: https://claude.ai/code/session_y',
  );
  res = r.merge(['subj', '--squash']);
  t.isTrue(res.exitCode != 0, 'Session-Zeile nur im Ergebnis → Abbruch');
  t.isTrue(
    '${res.stderr}'.contains('Ergebnisnachricht') && r.hasBranch('subj'),
    'Ergebnisnachricht: Meldung, Branch bleibt',
  );
  t.eq(r.head(), start, 'Ergebnisnachricht: main zurückgesetzt');
  t.isTrue(
    r.git(['status', '--porcelain', '--untracked-files=no']).isEmpty,
    'Ergebnisnachricht: sauberer Baum',
  );
}

void _successes(SelfCheck t, _Repo r) {
  final start = r.head();
  var res = r.merge(['wrong-id', '--squash', '-m', 'WP: Squash']);
  t.isTrue(res.exitCode == 0, 'Squash mit alter Identität ok: ${res.stderr}');
  t.eq(
    r.git(['rev-list', '--count', '$start..HEAD']),
    '1',
    'Squash: ein Commit',
  );
  t.isTrue(
    File('${r.dir.path}/b.txt').existsSync(),
    'Squash: Datei übernommen',
  );
  t.isTrue(!r.hasBranch('wrong-id'), 'Squash: Branch gelöscht');
  t.isTrue(
    !r.git(['log', '-1', '--format=%B']).contains('Claude-Session'),
    'Squash: keine Session-Zeile',
  );
  t.eq(
    r.git(['log', '-1', '--format=%B']),
    'WP: Squash\n\n$_trailer',
    'Squash: Nachricht mit genau einem Trailer',
  );
  t.eq(
    r.git(['log', '-1', '--format=%an']),
    _good,
    'Squash: globale Identität',
  );

  r.branch('ok', 'd.txt', 'feat');
  res = r.merge(['ok', '--keep']);
  t.isTrue(res.exitCode == 0, 'no-ff-Merge ok: ${res.stderr}');
  t.eq(
    r.git(['rev-list', '--parents', '-1', 'HEAD']).split(' ').length,
    3,
    'no-ff: zwei Eltern',
  );
  t.isTrue(r.hasBranch('ok'), '--keep behält den Branch');
  t.eq(
    r.git(['log', '-1', '--format=%B']),
    "Merge branch 'ok'\n\n$_trailer",
    'no-ff: Nachricht mit genau einem Trailer',
  );

  // Trägt -m den Trailer schon, wird er nicht verdoppelt.
  r.branch('tr', 'h.txt', 'feat');
  res = r.merge(['tr', '--squash', '-m', 'WP: Mit\n\n$_trailer']);
  t.isTrue(res.exitCode == 0, 'Squash mit vorhandenem Trailer ok');
  t.eq(
    r.git(['log', '-1', '--format=%B']),
    'WP: Mit\n\n$_trailer',
    'vorhandener Trailer wird nicht verdoppelt',
  );

  final before = r.head();
  r.branch('red', 'e.txt', 'feat');
  res = r.merge(['red'], extra: {'MERGE_WP_GATE': 'false'});
  t.isTrue(
    res.exitCode != 0 && r.hasBranch('red'),
    'rotes Gate → Abbruch, Branch bleibt',
  );
  r.git(['reset', '-q', '--hard', before]);
}

void _conflicts(SelfCheck t, _Repo r) {
  r.git(['checkout', '-q', '-b', 'k1', 'main']);
  r.commit('a.txt', 'k1\n', 'k1');
  r.git(['checkout', '-q', 'main']);
  r.commit('a.txt', 'main\n', 'main-change');
  final c = r.head();
  var res = r.merge(['k1']);
  t.isTrue(res.exitCode != 0, 'Konflikt in normaler Datei → Abbruch');
  t.eq(r.head(), c, 'Konflikt: zurückgesetzt');
  t.isTrue(
    r.git(['status', '--porcelain', '--untracked-files=no']).isEmpty,
    'Konflikt: sauberer Baum',
  );

  // Konflikt nur in einer linguist-generated-Datei: der Hook löst ihn.
  r.commit('.gitattributes', 'g.txt linguist-generated\n', 'attr');
  r.commit('g.txt', 'base\n', 'g');
  File('${r.dir.path}/tool/regen_generated.sh')
      .writeAsStringSync('for f in "\$@"; do echo regen > "\$f"; done\n');
  r.git(['add', 'tool']);
  r.git(['commit', '-q', '-m', 'regen']);
  r.git(['checkout', '-q', '-b', 'gen', 'main']);
  r.commit('g.txt', 'gen\n', 'gen');
  r.git(['checkout', '-q', 'main']);
  r.commit('g.txt', 'main2\n', 'main-gen');
  res = r.merge(['gen']);
  t.isTrue(
    res.exitCode == 0,
    'Konflikt nur in generierter Datei gelöst: ${res.stderr}',
  );
  t.eq(
    File('${r.dir.path}/g.txt').readAsStringSync(),
    'regen\n',
    'generierte Datei vom Hook erzeugt',
  );
}

/// Schlagen `check_registry --fix` oder `gen_docs` fehl, bricht der Merge ab
/// und setzt zurück (statt den Fehler zu verschlucken).
void _generators(SelfCheck t, _Repo r) {
  void tool(String name, int code) {
    File('${r.dir.path}/tool/$name.dart').writeAsStringSync(
      "import 'dart:io';\nvoid main() { stderr.writeln('kaputt $name'); "
      'exit($code); }\n',
    );
    r.git(['add', 'tool']);
    r.git(['commit', '-q', '-m', '$name $code']);
  }

  tool('check_registry', 1);
  tool('gen_docs', 0);
  r.branch('reg', 'i.txt', 'feat');
  var start = r.head();
  var res = r.merge(['reg']);
  t.isTrue(res.exitCode != 0, 'check_registry --fix rot → Abbruch');
  t.isTrue(
    '${res.stderr}'.contains('kaputt check_registry'),
    'check_registry: Fehlerausgabe wird gezeigt',
  );
  t.eq(r.head(), start, 'check_registry rot: main zurückgesetzt');
  t.isTrue(r.hasBranch('reg'), 'check_registry rot: Branch bleibt');

  tool('check_registry', 0);
  tool('gen_docs', 1);
  r.branch('docs', 'j.txt', 'feat');
  start = r.head();
  res = r.merge(['docs']);
  t.isTrue(res.exitCode != 0, 'gen_docs rot → Abbruch');
  t.isTrue(
    '${res.stderr}'.contains('kaputt gen_docs'),
    'gen_docs: Fehlerausgabe wird gezeigt',
  );
  t.eq(r.head(), start, 'gen_docs rot: main zurückgesetzt');

  tool('gen_docs', 0);
  r.branch('fine', 'k.txt', 'feat');
  res = r.merge(['fine']);
  t.isTrue(res.exitCode == 0, 'beide Erzeuger grün → Merge ok: ${res.stderr}');
}

/// Ohne grünen gate-Lauf auf genau dem Branch-SHA wird nicht gemergt.
void _ciChecks(SelfCheck t, _Repo r) {
  final start = r.head();
  r.branch('ci', 'ci.txt', 'feat');
  final sha = r.git(['rev-parse', 'ci']);
  const old = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  void rejects(String what, String cmd) {
    final res = r.merge(['ci'], extra: {'MERGE_WP_CI': cmd});
    t.isTrue(
      res.exitCode != 0 && '${res.stderr}'.contains('CI'),
      '$what → Abbruch mit CI-Meldung',
    );
    t.eq(r.head(), start, '$what: main unverändert');
    t.isTrue(r.hasBranch('ci'), '$what: Branch bleibt');
  }

  rejects(
    'roter CI-Lauf',
    ciRuns(['2026-01-01T00:00:00Z $sha ci completed failure']),
  );
  rejects('fehlender CI-Lauf', 'true');
  rejects(
    'abgebrochener Lauf',
    ciRuns(['2026-01-01T00:00:00Z $sha ci completed cancelled']),
  );
  rejects(
    'laufender Lauf',
    ciRuns(['2026-01-01T00:00:00Z $sha ci in_progress ']),
  );
  rejects(
    'grüner Lauf auf anderem Branch',
    ciRuns(['2026-01-01T00:00:00Z $sha other completed success']),
  );
  rejects(
    'grüner Lauf auf anderem SHA',
    ciRuns(['2026-01-01T00:00:00Z $old ci completed success']),
  );
  rejects(
    'neuester Lauf rot (älterer grün)',
    ciRuns([
      '2026-01-01T00:00:00Z $sha ci completed success',
      '2026-01-02T00:00:00Z $sha ci completed failure',
    ]),
  );
  rejects('CI-Abfrage schlägt fehl', 'false');
  final res = r.merge(['ci', '--dry-run'], extra: {'MERGE_WP_CI': 'true'});
  t.isTrue(res.exitCode != 0, 'dry-run prüft das CI ebenfalls');
  _ciMerges(t, r, start, sha, old);
}

/// Grüne Läufe: Merge, Tree-Notiz, rotes Gate, Branch-HEAD = Merge von main.
void _ciMerges(SelfCheck t, _Repo r, String start, String sha, String old) {
  var res = r.merge(
    ['ci', '--keep'],
    extra: {
      'MERGE_WP_CI': ciRuns([
        '2026-01-02T00:00:00Z $sha ci completed success',
        '2026-01-01T00:00:00Z $sha ci completed failure',
        '2026-01-03T00:00:00Z $old ci completed failure',
      ]),
    },
  );
  t.isTrue(res.exitCode == 0, 'neuester Lauf grün → Merge: ${res.stderr}');
  final tree = r.git(['rev-parse', 'HEAD^{tree}']);
  final common = r.git([
    'rev-parse',
    '--path-format=absolute',
    '--git-common-dir',
  ]);
  t.eq(
    File('$common/wendelin-merge-ok').readAsStringSync().trim(),
    tree,
    'Tree des Merge-Ergebnisses nach dem Gate notiert',
  );

  // Rotes Gate: nichts notiert.
  final noted = File('$common/wendelin-merge-ok').readAsStringSync();
  r.branch('ci2', 'ci2.txt', 'feat');
  res = r.merge(['ci2'], extra: {'MERGE_WP_GATE': 'false'});
  t.isTrue(res.exitCode != 0, 'rotes Gate: Abbruch');
  t.eq(
    File('$common/wendelin-merge-ok').readAsStringSync(),
    noted,
    'rotes Gate: kein Tree notiert',
  );
  r.git(['reset', '-q', '--hard', start]);
  r.git(['branch', '-D', 'ci2']);

  // Branch-HEAD ist ein Merge von main: CI-Beleg und Merge funktionieren.
  r.git(['checkout', '-q', '-b', 'ci3', 'main']);
  r.commit('ci3.txt', 'x\n', 'feat');
  r.git(['checkout', '-q', 'main']);
  r.commit('main-side.txt', 'm\n', 'main moves');
  r.git(['checkout', '-q', 'ci3']);
  r.git(['merge', '-q', '--no-ff', '-m', 'Merge main\n\n$_trailer', 'main']);
  r.git(['checkout', '-q', 'main']);
  res = r.merge(['ci3']);
  t.isTrue(
    res.exitCode == 0,
    'Branch-HEAD = Merge von main: Merge ok: ${res.stderr}',
  );
  t.isTrue(!r.hasBranch('ci3'), 'Merge-HEAD-Branch: aufgeräumt');
}
