// Selbsttests von tool/cleanup_wt.sh (WP109) in einem Wegwerf-Repo mit
// lokalem Bare-Remote. Nie gegen das echte Repo oder Remote.
import 'dart:io';

import 'sandbox.dart';
import 'self_check.dart';

void cleanupChecks(SelfCheck t) {
  t.group('cleanup_wt.sh');
  final root = Directory.systemTemp.createTempSync('cleanup_selftest_');
  try {
    final c = _Env(root.path);
    c.setUp();
    _refusals(t, c);
    _merged(t, c);
    _remote(t, c);
    _squash(t, c);
    _viaMergeWp(t, c);
    _detached(t, c);
    _amendedSquash(t, c);
    _lease(t, c);
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Hauptrepo `main/`, Remote `remote.git`, Worktrees unter `james-wt/`.
final class _Env {
  _Env(this.root)
    : r = Sandbox(Directory('$root/main')..createSync()),
      wt = '$root/james-wt',
      script = File('tool/cleanup_wt.sh').absolute.path;

  final String root;
  final Sandbox r;
  final String wt;
  final String script;

  void setUp() {
    Process.runSync('git', ['init', '-q', '--bare', '$root/remote.git']);
    r.git(['init', '-q', '-b', 'main']);
    r.git(['remote', 'add', 'origin', '$root/remote.git']);
    r.commit('a.txt', 'a\n');
    r.git(['push', '-q', 'origin', 'main']);
    Directory('$wt/handoff').createSync(recursive: true);
  }

  ProcessResult run(List<String> a) => Process.runSync(
    'bash',
    [script, ...a],
    workingDirectory: r.dir.path,
    environment: r.env,
  );

  bool exists(String p) =>
      FileSystemEntity.typeSync(p) != FileSystemEntityType.notFound;

  String remoteBranches() => r.git(['ls-remote', '--heads', 'origin']);

  /// Branch `wp/<nr>-<slug>` (zwei Commits, gepusht), Worktree, Prüf-Worktree, Handoff.
  void pkg(String nr, String slug) {
    final b = 'wp/$nr-$slug';
    r.git(['checkout', '-q', '-b', b, 'main']);
    r.commit('f$nr.txt', '$nr\n');
    r.commit('g$nr.txt', '$nr\n');
    r.git(['push', '-q', 'origin', b]);
    r.git(['checkout', '-q', 'main']);
    r.git(['worktree', 'add', '-q', '$wt/wp$nr', b]);
    r.git(['worktree', 'add', '-q', '--detach', '$wt/rev-wp$nr', b]);
    for (final f in ['wp$nr.md', 'wp$nr-session-prompt.md', 'wp$nr-log.txt']) {
      File('$wt/handoff/$f').writeAsStringSync('h\n');
    }
  }

  /// Alles, was cleanup berühren darf, als ein Vergleichswert.
  String snapshot() {
    final files = Directory(
      '$wt/handoff',
    ).listSync().map((e) => e.path).toList()..sort();
    return '${r.git(['branch', '--list', '-a'])}|${r.git(['worktree', 'list'])}|'
        '$files|${remoteBranches()}';
  }
}

void _refusals(SelfCheck t, _Env c) {
  for (final p in [('7', 'foo'), ('70', 'bar'), ('43', 'spike-attestation')]) {
    c.pkg(p.$1, p.$2);
  }
  c.pkg('10', 'zehn');
  c.pkg('109', 'leit');
  c.r.git(['merge', '-q', '--no-ff', '-m', 'Merge 7', 'wp/7-foo']);
  c.r.git(['merge', '-q', '--no-ff', '-m', 'Merge 10', 'wp/10-zehn']);
  final before = c.snapshot();

  var res = c.run(['wp7']);
  t.isTrue(
    res.exitCode == 0 &&
        '${res.stdout}'.contains('Probelauf') &&
        c.snapshot() == before,
    'ohne --apply bleibt alles bestehen (Probelauf): ${res.stderr}',
  );
  t.isTrue(
    '${res.stdout}'.contains('wp7') && !'${res.stdout}'.contains('wp70'),
    'Probelauf nennt nur die Pfade von wp7',
  );
  for (final arg in ['wp70', 'wp/43-spike-attestation', 'wp43', 'wp109']) {
    res = c.run([arg, '--apply']);
    t.isTrue(
      res.exitCode != 0 &&
          '${res.stderr}'.contains('nicht in') &&
          c.snapshot() == before,
      'ungemergt ($arg) mit --apply: nichts gelöscht',
    );
  }
  File('${c.wt}/wp7/neu.txt').writeAsStringSync('wip\n');
  res = c.run(['wp7', '--apply']);
  t.isTrue(
    res.exitCode != 0 &&
        '${res.stderr}'.contains('nicht sauber') &&
        c.snapshot() == before,
    'schmutziger Worktree: nichts gelöscht (alles oder nichts)',
  );
  File('${c.wt}/wp7/neu.txt').deleteSync();
}

void _merged(SelfCheck t, _Env c) {
  final wt = c.wt;
  final res = c.run(['wp7', '--apply', '--no-remote']);
  t.eq(res.exitCode, 0, 'gemergt (no-ff) mit --apply: ok ${res.stderr}');
  t.isTrue(
    !c.exists('$wt/wp7') &&
        !c.exists('$wt/rev-wp7') &&
        !c.r.hasRef('refs/heads/wp/7-foo'),
    'Worktree, Prüf-Worktree und lokaler Branch entfernt',
  );
  t.isTrue(
    !c.exists('$wt/handoff/wp7.md') &&
        !c.exists('$wt/handoff/wp7-session-prompt.md') &&
        !c.exists('$wt/handoff/wp7-log.txt'),
    'handoff/wp7.md und wp7-* entfernt',
  );
  t.isTrue(
    c.exists('$wt/wp70') &&
        c.exists('$wt/rev-wp70') &&
        c.exists('$wt/handoff/wp70.md') &&
        c.exists('$wt/handoff/wp70-log.txt') &&
        c.r.hasRef('refs/heads/wp/70-bar') &&
        c.exists('$wt/wp43') &&
        c.r.hasRef('refs/heads/wp/43-spike-attestation') &&
        c.exists('$wt/wp109') &&
        c.exists('$wt/handoff/wp109.md'),
    'wp70, wp43, wp109 unberührt (wp7 ≠ wp70)',
  );
}

void _remote(SelfCheck t, _Env c) {
  final wt = c.wt;
  t.isTrue(
    c.remoteBranches().contains('wp/7-foo'),
    '--no-remote lässt den Remote-Branch',
  );
  var res = c.run(['wp7', '--apply']);
  t.isTrue(
    c.remoteBranches().contains('wp/7-foo') &&
        '${res.stdout}'.contains('bleibt'),
    'Remote-Branch bleibt, solange origin/main ihn nicht enthält',
  );
  c.r.git(['push', '-q', 'origin', 'main']);
  res = c.run(['wp7', '--apply']);
  t.isTrue(
    res.exitCode == 0 &&
        !c.remoteBranches().contains('wp/7-foo') &&
        c.remoteBranches().contains('wp/70-bar'),
    'nach dem main-Push: Remote-Branch weg, andere bleiben: ${res.stderr}',
  );
  res = c.run(['wp10', '--apply']);
  t.isTrue(
    res.exitCode == 0 &&
        !c.exists('$wt/wp10') &&
        !c.exists('$wt/handoff/wp10.md') &&
        c.exists('$wt/wp109') &&
        c.exists('$wt/handoff/wp109.md') &&
        c.exists('$wt/handoff/wp109-log.txt') &&
        c.r.hasRef('refs/heads/wp/109-leit'),
    'wp10 räumt nur wp10 auf, nicht wp109',
  );
}

void _squash(SelfCheck t, _Env c) {
  final wt = c.wt;
  c.pkg('8', 'sq');
  c.r.git(['merge', '--squash', 'wp/8-sq']);
  c.r.git(['commit', '-q', '-m', 'Squash 8\n\n$sbTrailer']);
  c.r.git(['push', '-q', 'origin', 'main']);
  var res = c.run(['wp/8-sq', '--apply']);
  t.isTrue(
    res.exitCode == 0 &&
        !c.r.hasRef('refs/heads/wp/8-sq') &&
        !c.exists('$wt/wp8') &&
        !c.exists('$wt/handoff/wp8.md') &&
        !c.remoteBranches().contains('wp/8-sq'),
    'Squash-Merge (Patch-ID) erkannt: lokal und remote entfernt: ${res.stderr}',
  );
  c.pkg('11', 'sq2');
  c.r.git(['merge', '--squash', 'wp/11-sq2']);
  c.r.git(['commit', '-q', '-m', 'Squash 11\n\n$sbTrailer']);
  c.r.commit('wp11-extra.txt', 'x\n', cwd: '$wt/wp11');
  res = c.run(['wp11', '--apply']);
  t.isTrue(
    res.exitCode != 0 &&
        c.r.hasRef('refs/heads/wp/11-sq2') &&
        c.exists('$wt/wp11'),
    'nach dem Squash nachgelegter Commit: ungemergt, nichts gelöscht',
  );
}

void _viaMergeWp(SelfCheck t, _Env c) {
  final wt = c.wt;
  c.pkg('12', 'viaMerge');
  final res = Process.runSync(
    'bash',
    [
      File('tool/merge_wp.sh').absolute.path,
      'wp/12-viaMerge',
      '--squash',
      '-m',
      'WP12: Squash',
    ],
    workingDirectory: c.r.dir.path,
    environment: {
      ...c.r.env,
      'MERGE_WP_GATE': 'true',
      'MERGE_WP_CLEANUP': c.script,
      'MERGE_WP_CI': r'printf "2026-01-01T00:00:00Z\t%s\t%s\tcompleted\tsuccess\n" "$SHA" "$BRANCH"',
    },
  );
  t.isTrue(
    res.exitCode == 0 &&
        !c.r.hasRef('refs/heads/wp/12-viaMerge') &&
        !c.exists('$wt/wp12') &&
        !c.exists('$wt/rev-wp12') &&
        !c.exists('$wt/handoff/wp12.md') &&
        c.remoteBranches().contains('wp/12-viaMerge'),
    'merge_wp --squash räumt lokal über cleanup_wt.sh auf, Remote bleibt: '
    '${res.stderr}',
  );
  c.r.git(['push', '-q', 'origin', 'main']);
  final again = c.run(['wp12', '--apply']);
  t.isTrue(
    again.exitCode == 0 && !c.remoteBranches().contains('wp/12-viaMerge'),
    'nach dem Push: Remote-Branch per Squash-Vermerk entfernt: ${again.stderr}',
  );
  t.isTrue(
    c.run(['foo/bar', '--apply']).exitCode != 0 &&
        c.run(['wp999', '--apply']).exitCode == 0,
    'ungültiger Name abgelehnt, unbekanntes Paket: nichts zu tun',
  );
}

/// Detached Prüf-Worktree auf ungemergtem Commit: nichts wird gelöscht.
void _detached(SelfCheck t, _Env c) {
  c.pkg('13', 'det');
  c.r.git(['merge', '-q', '--no-ff', '-m', 'Merge 13', 'wp/13-det']);
  c.r.git(['checkout', '-q', '-b', 'fremd', 'main~1']);
  c.r.commit('fremd.txt', 'f\n');
  c.r.git(['checkout', '-q', 'main']);
  c.r.git(['-C', '${c.wt}/rev-wp13', 'checkout', '-q', '--detach', 'fremd']);
  final before = c.snapshot();
  final res = c.run(['wp13', '--apply', '--no-remote']);
  t.isTrue(
    res.exitCode != 0 &&
        '${res.stderr}'.contains('nicht in') &&
        c.snapshot() == before,
    'detached rev-wp auf ungemergtem Commit: nichts gelöscht: ${res.stderr}',
  );
  if (!c.exists('${c.wt}/rev-wp13')) return;
  c.r.git([
    '-C',
    '${c.wt}/rev-wp13',
    'checkout',
    '-q',
    '--detach',
    'wp/13-det',
  ]);
  t.eq(
    c.run(['wp13', '--apply', '--no-remote']).exitCode,
    0,
    'detached rev-wp auf gemergtem Stand: aufgeräumt',
  );
}

/// Squash mit zusätzlicher Datei (gen_docs) und Amend: Vermerk trägt den Tree.
void _amendedSquash(SelfCheck t, _Env c) {
  final common = c.r.git([
    'rev-parse',
    '--path-format=absolute',
    '--git-common-dir',
  ]);
  String squash(String nr, String slug) {
    c.pkg(nr, slug);
    final tip = c.r.git(['rev-parse', 'wp/$nr-$slug']);
    c.r.git(['merge', '--squash', 'wp/$nr-$slug']);
    c.r.commit('docs/gen$nr.md', 'g\n', msg: 'Squash $nr\n\n$sbTrailer');
    final commit = c.r.head();
    final tree = c.r.git(['rev-parse', 'HEAD^{tree}']);
    File('$common/wendelin-merged-branches')
        .writeAsStringSync('$tip $commit $tree\n', mode: FileMode.append);
    return commit;
  }

  squash('14', 'am');
  c.r.git(['commit', '-q', '--amend', '-m', 'Andere Nachricht\n\n$sbTrailer']);
  c.r.git(['push', '-q', 'origin', 'main']);
  var res = c.run(['wp14', '--apply']);
  t.isTrue(
    res.exitCode == 0 && !c.r.hasRef('refs/heads/wp/14-am'),
    'Squash + gen_docs-Datei + Amend: Vermerk mit Tree erkannt: ${res.stderr}',
  );
  squash('15', 'rs');
  c.r.git(['reset', '-q', '--hard', 'HEAD~1']);
  c.r.commit('other15.txt', 'o\n'); // Basis hat Commits seit der Merge-Basis
  res = c.run(['wp15', '--apply']);
  t.isTrue(
    res.exitCode != 0 &&
        c.r.hasRef('refs/heads/wp/15-rs') &&
        c.exists('${c.wt}/wp15'),
    'Vermerk ohne Merge-Commit/Tree in der Basis (zurückgesetzt): ungemergt',
  );
}

/// Remote-Löschen nur, wenn der Remote-Branch noch auf dem geprüften Tip steht.
void _lease(SelfCheck t, _Env c) {
  c.pkg('16', 'lease');
  c.r.git(['merge', '-q', '--no-ff', '-m', 'Merge 16', 'wp/16-lease']);
  c.r.git(['push', '-q', 'origin', 'main']);
  const ref = 'refs/remotes/origin/wp/16-lease';
  final tip = c.r.git(['rev-parse', 'wp/16-lease']);
  final tree = c.r.git(['rev-parse', '$tip^{tree}']);
  final extra = c.r.git(['commit-tree', tree, '-p', tip, '-m', 'neu']);
  c.r.git(['push', '-q', 'origin', '$extra:refs/heads/wp/16-lease']);
  c.r.git(['update-ref', ref, tip]); // veralteter Tracking-Stand
  c.run(['wp16', '--apply']);
  t.isTrue(
    c.remoteBranches().contains(extra),
    'Remote-Branch, der inzwischen weitergewandert ist, bleibt (Lease)',
  );
}
