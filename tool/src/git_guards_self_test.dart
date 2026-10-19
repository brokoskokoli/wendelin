// Selbsttests von tool/hooks/pre-push.sh und tool/check_commit_identity.sh
// (WP109) in temporären Repos.
import 'dart:io';

import 'sandbox.dart';
import 'self_check.dart';

void gitGuardsChecks(SelfCheck t) {
  _prePush(t);
  _identity(t);
}

/// Repo für den pre-push-Hook; [push] liefert den Exit-Code des Hooks.
final class _PushRepo {
  _PushRepo(this.r) : hook = File('tool/hooks/pre-push.sh').absolute.path {
    r.git(['init', '-q', '-b', 'main']);
    r.commit('a.txt', 'a\n');
    c0 = r.head();
    common = r.git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
  }

  final Sandbox r;
  final String hook;
  late final String c0;
  late final String common;

  /// Notiert den Tree von [rev] wie merge_wp.sh.
  void note(String rev) => File('$common/wendelin-merge-ok').writeAsStringSync(
    '${r.git(['rev-parse', '$rev^{tree}'])}\n',
    mode: FileMode.append,
  );

  int push(String ref, String lsha, {bool allow = false}) => Process.runSync(
    'bash',
    ['-c', 'printf "%s\\n" "\$LINE" | sh "\$HOOK" origin x'],
    workingDirectory: r.dir.path,
    environment: {
      ...r.env,
      'LINE': '$ref $lsha $ref $c0',
      'HOOK': hook,
      if (allow) 'WENDELIN_PUSH_MAIN': '1',
    },
  ).exitCode;
}

void _prePush(SelfCheck t) {
  t.group('pre-push');
  final d = Directory.systemTemp.createTempSync('prepush_selftest_');
  try {
    final p = _PushRepo(Sandbox(d));
    _prePushPlain(t, p);
    _prePushNoted(t, p);
    _prePushMerge(t, p);
  } finally {
    d.deleteSync(recursive: true);
  }
}

void _prePushPlain(SelfCheck t, _PushRepo p) {
  final r = p.r;
  const main = 'refs/heads/main';
  r.git(['checkout', '-q', '-b', 'docs']);
  r.commit('docs/x.md', 'd\n');
  r.commit('Voice Agent App – Gesamtkonzept.md', 'k\n');
  t.isTrue(
    p.push(main, r.head()) != 0,
    'main ohne Variable: abgelehnt (auch reine Doku)',
  );
  t.eq(
    p.push(main, r.head(), allow: true),
    0,
    'Doku-Commits mit Variable: erlaubt',
  );
  r.commit('code.dart', 'c\n');
  t.isTrue(
    p.push(main, r.head(), allow: true) != 0,
    'Code-Commit ohne notierten Tree: abgelehnt',
  );
  t.eq(p.push('refs/heads/wp/1-x', r.head()), 0, 'wp/*-Push: frei');
  t.eq(p.push('refs/heads/other', r.head()), 0, 'anderer Branch: frei');
  t.eq(p.push('refs/tags/v1', r.head()), 0, 'Tag: frei');
  t.eq(
    p.push('refs/heads/wp/1-x', sbZero),
    0,
    'Löschen eines wp/*-Branches: frei',
  );
  t.isTrue(
    p.push(main, sbZero, allow: true) != 0 && p.push(main, sbZero) != 0,
    'main löschen: abgelehnt',
  );
}

void _prePushNoted(SelfCheck t, _PushRepo p) {
  final r = p.r;
  const main = 'refs/heads/main';
  p.note('HEAD');
  t.eq(p.push(main, r.head(), allow: true), 0, 'notierter Tree: erlaubt');
  r.git(['commit', '-q', '--amend', '-m', 'andere Nachricht\n\n$sbTrailer']);
  t.eq(
    p.push(main, r.head(), allow: true),
    0,
    'Amend der Nachricht: Tree zählt weiter',
  );
  t.isTrue(
    p.push(main, r.head()) != 0,
    'notierter Tree ohne Variable: abgelehnt',
  );
  r.commit('docs/more.md', 'm\n');
  t.eq(
    p.push(main, r.head(), allow: true),
    0,
    'Status-Commit (Doku) nach der Freigabe: erlaubt',
  );
  r.commit('late.dart', 'l\n');
  t.isTrue(
    p.push(main, r.head(), allow: true) != 0,
    'Code-Commit nach der Freigabe: abgelehnt',
  );
}

void _prePushMerge(SelfCheck t, _PushRepo p) {
  final r = p.r;
  const main = 'refs/heads/main';
  r.git(['checkout', '-q', '-B', 'main', p.c0]);
  r.git(['checkout', '-q', '-b', 'feat']);
  r.commit('f1.dart', '1\n');
  r.commit('f2.dart', '2\n');
  r.git(['checkout', '-q', 'main']);
  r.git(['merge', '-q', '--no-ff', '-m', 'Merge feat\n\n$sbTrailer', 'feat']);
  t.isTrue(
    p.push(main, r.head(), allow: true) != 0,
    'Merge ohne notierten Tree: abgelehnt',
  );
  p.note('HEAD');
  t.eq(
    p.push(main, r.head(), allow: true),
    0,
    'Merge mit notiertem Tree: erlaubt (Branch-Commits gedeckt)',
  );
  r.commit('docs/s.md', 's\n');
  t.eq(
    p.push(main, r.head(), allow: true),
    0,
    'Merge plus Status-Commit: erlaubt',
  );
}

void _identity(SelfCheck t) {
  t.group('CI-Commit-Identität');
  final d = Directory.systemTemp.createTempSync('identity_selftest_');
  try {
    final r = Sandbox(d)..git(['init', '-q', '-b', 'main']);
    r.commit('a.txt', 'a\n');
    final base = r.head();
    final script = File('tool/check_commit_identity.sh').absolute.path;
    int check(String range, [Map<String, String> env = const {}]) =>
        Process.runSync(
          'bash',
          [script, range],
          workingDirectory: d.path,
          environment: {...r.env, ...env},
        ).exitCode;
    int branch(String name, void Function() make) {
      r.git(['checkout', '-q', '-b', name, base]);
      make();
      final rc = check('$base..HEAD');
      r.git(['checkout', '-q', 'main']);
      return rc;
    }

    _identityCases(t, r, base, check, branch);
    _identityCi(t, r, base, script);
  } finally {
    d.deleteSync(recursive: true);
  }
}

void _identityCases(
  SelfCheck t,
  Sandbox r,
  String base,
  int Function(String, [Map<String, String>]) check,
  int Function(String, void Function()) branch,
) {
  const foreign = {
    'GIT_AUTHOR_NAME': 'Fremd',
    'GIT_AUTHOR_EMAIL': 'fremd@example.org',
  };
  const foreignCommitter = {
    'GIT_COMMITTER_NAME': 'Fremd',
    'GIT_COMMITTER_EMAIL': 'fremd@example.org',
  };
  void c(String msg, [Map<String, String> extra = const {}]) =>
      r.commit('b', msg, msg: msg, extra: extra);
  t.eq(check('$base..$base'), 0, 'leerer Bereich ist grün');
  t.eq(
    branch('ok', () {
      c('x\n\n$sbTrailer');
      r.commit('c', '2', msg: 'y\n\n$sbTrailer');
    }),
    0,
    'zwei saubere Commits: grün',
  );
  t.eq(branch('author', () => c('x\n\n$sbTrailer', foreign)), 1, 'Autor: rot');
  t.eq(
    branch('committer', () => c('x\n\n$sbTrailer', foreignCommitter)),
    1,
    'fremder Committer: rot',
  );
  t.eq(
    branch('two', () => c('x\n\n$sbTrailer\n$sbTrailer')),
    1,
    'zweiter Trailer: rot',
  );
  t.eq(
    branch(
      'other',
      () => c('x\n\n$sbTrailer\nCo-Authored-By: Jemand <j@example.org>'),
    ),
    1,
    'zweiter Trailer mit anderem Namen: rot',
  );
  t.eq(
    branch(
      'wrong',
      () => c('x\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>'),
    ),
    1,
    'abweichende Schreibweise des Trailers: rot',
  );
  t.eq(branch('none', () => c('x')), 1, 'kein Trailer: rot');
  t.eq(
    branch(
      'session',
      () => c(
        'x\n\n$sbTrailer\nClaude-Session: https://claude.ai/code/session_x',
      ),
    ),
    1,
    'Session-Zeile: rot',
  );
  t.eq(
    branch('late', () {
      c('gut\n\n$sbTrailer');
      r.commit('c', '2', msg: 'schlecht');
    }),
    1,
    'ein schlechter Commit unter mehreren: rot',
  );
}

void _identityCi(SelfCheck t, Sandbox r, String base, String script) {
  r.git(['checkout', '-q', '-b', 'wp/9-x', base]);
  r.commit('b', '1', msg: 'schlecht');
  r.git(['update-ref', 'refs/remotes/origin/main', base]);
  final bad = r.head();
  int ci(Map<String, String> env) => Process.runSync(
    'bash',
    [script, '--ci'],
    workingDirectory: r.dir.path,
    environment: {...r.env, ...env},
  ).exitCode;
  const main = 'refs/heads/main';
  t.eq(
    ci({'REF': 'refs/heads/wp/9-x', 'AFTER': bad}),
    1,
    '--ci auf Branch: merge-base..Kopf, rot',
  );
  t.eq(
    ci({'REF': 'refs/heads/wp/9-x', 'PR_HEAD': bad, 'AFTER': 'x'}),
    1,
    '--ci im PR: Kopf des PR, rot',
  );
  t.eq(
    ci({'REF': main, 'BEFORE': base, 'AFTER': bad}),
    1,
    '--ci auf main: before..after, rot',
  );
  t.eq(
    ci({'REF': main, 'BEFORE': sbZero, 'AFTER': bad}),
    1,
    '--ci auf main ohne before: letzter Commit, rot',
  );
  t.eq(
    ci({'REF': main, 'BEFORE': bad, 'AFTER': bad}),
    0,
    '--ci auf main ohne neue Commits: grün',
  );
}
