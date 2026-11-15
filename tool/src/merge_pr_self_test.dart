// Selbsttests von tool/merge_pr.sh in temporären Git-Repos (mit einem
// lokalen Bare-Repo als origin, CI- und PR-Abfragen gefälscht).
import 'dart:io';

import 'sandbox.dart';
import 'self_check.dart';

const _model = 'Opus 5.5';
const _trailer = 'Co-Authored-By: Claude $_model <noreply@anthropic.com>';

/// CI-Ersatz mit festen Laufzeilen
/// (`<createdAt> <sha> <branch> <status> <conclusion>`, Leerzeichen → Tabs).
String _ciRuns(List<String> rows) =>
    "printf '%s\\n' ${rows.map((r) => "'${r.replaceAll(' ', '\t')}'").join(' ')}";

/// Ein grüner Lauf auf genau dem Kopf-SHA.
const _ciGreen =
    r'printf "2026-01-01T00:00:00Z\t%s\t%s\tcompleted\tsuccess\t1\n" "$SHA" "$BRANCH"';

final class _Repo {
  _Repo(this.r, this.script) {
    final origin = '${r.dir.path}/origin.git';
    Process.runSync('git', ['init', '-q', '--bare', '-b', 'main', origin]);
    work = Directory('${r.dir.path}/work')..createSync();
    git(['init', '-q', '-b', 'main']);
    r.commit('a.txt', 'a\n', cwd: work.path);
    git(['remote', 'add', 'origin', origin]);
    git(['push', '-q', 'origin', 'main']);
    git(['fetch', '-q', 'origin']);
    common = git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
  }

  final Sandbox r;
  final String script;
  late final Directory work;
  late final String common;

  File get okFile => File('$common/wendelin-merge-ok');
  String ok() => okFile.existsSync() ? okFile.readAsStringSync() : '<keine>';

  String git(List<String> a, {Map<String, String> extra = const {}}) =>
      r.git(a, extra: extra, cwd: work.path);

  String head() => git(['rev-parse', 'HEAD']);

  /// Legt den PR-Branch [name] auf origin/main an, pusht ihn und kehrt nach
  /// main zurück; liefert den Kopf-SHA.
  String pr(
    String name,
    Map<String, String> files, {
    Map<String, String> extra = const {},
  }) {
    git(['checkout', '-q', '-b', name, 'origin/main']);
    for (final e in files.entries) {
      r.commit(
        e.key,
        e.value,
        msg: 'feat: $name\n\n$sbTrailer',
        extra: extra,
        cwd: work.path,
      );
    }
    git(['push', '-q', 'origin', name]);
    git(['checkout', '-q', 'main']);
    return git(['rev-parse', name]);
  }

  /// PR-Ersatz: eine Zeile wie `gh pr view … @tsv`.
  static String view(
    String branch,
    String sha, {
    String title = 'feat: Titel',
    String state = 'OPEN',
    String base = 'main',
  }) =>
      "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' '$state' '$base' '$branch' "
      "'$sha' '$title'";

  ProcessResult merge(List<String> args, Map<String, String> extra) =>
      Process.runSync(
        'bash',
        [script, ...args],
        workingDirectory: work.path,
        environment: {
          ...r.env,
          'MERGE_PR_CI': _ciGreen,
          'MERGE_PR_CI_MODE': 'echo full',
          ...extra,
        },
      );
}

void mergePrChecks(SelfCheck t) {
  t.group('merge_pr.sh');
  final d = Directory.systemTemp.createTempSync('merge_pr_');
  try {
    final m = _Repo(Sandbox(d), File('tool/merge_pr.sh').absolute.path);
    _rejections(t, m);
    _ciRejections(t, m);
    _successes(t, m);
  } finally {
    d.deleteSync(recursive: true);
  }
}

/// Erwartet einen Abbruch mit [hint] in der Meldung, ohne Merge-Commit und
/// ohne neue Freigabe.
void _rejects(
  SelfCheck t,
  _Repo m,
  String what,
  List<String> args,
  Map<String, String> extra,
  String hint,
) {
  final before = m.head();
  final ok = m.ok();
  final status = m.git(['status', '--porcelain', '--untracked-files=no']);
  final res = m.merge(args, extra);
  t.isTrue(
    res.exitCode != 0 && '${res.stderr}'.contains(hint),
    '$what → Abbruch mit Meldung „$hint“: ${res.stderr}',
  );
  t.isTrue(
    m.head() == before &&
        m.ok() == ok &&
        m.git(['status', '--porcelain', '--untracked-files=no']) == status,
    '$what: kein Merge-Commit, keine Freigabe, Baum unverändert',
  );
}

void _rejections(SelfCheck t, _Repo m) {
  final sha = m.pr('feat', {'lib.dart': 'x\n'});
  final view = {'MERGE_PR_VIEW': _Repo.view('feat', sha)};
  final args = ['7', '--model', _model];
  _rejects(t, m, '--model fehlt', ['7'], view, '--model fehlt');
  _rejects(t, m, '--model ohne Wert', ['7', '--model'], view, '--model');
  _rejects(t, m, '--model leer', ['7', '--model', ''], view, '--model fehlt');
  for (final bad in ['Gpt 4', 'Opus 5.5 <x@example.org>', '']) {
    _rejects(
      t,
      m,
      '--model „$bad“ ungültig',
      ['7', '--model=$bad'],
      view,
      '--model',
    );
  }
  _rejects(t, m, 'keine PR-Nummer', ['--model', _model], view, 'Aufruf');
  _rejects(
    t,
    m,
    'PR-Nummer keine Zahl',
    ['x7', '--model', _model],
    view,
    'keine Zahl',
  );
  _rejects(t, m, 'PR geschlossen', args, {
    'MERGE_PR_VIEW': _Repo.view('feat', sha, state: 'CLOSED'),
  }, 'nicht offen');
  _rejects(t, m, 'Basis nicht main', args, {
    'MERGE_PR_VIEW': _Repo.view('feat', sha, base: 'dev'),
  }, 'Basis');
  _rejects(t, m, 'lokaler Kopf ≠ PR-Kopf', args, {
    'MERGE_PR_VIEW': _Repo.view('feat', 'a' * 40),
  }, 'PR-Kopf');
  _rejects(t, m, 'PR-Abfrage schlägt fehl', args, {
    'MERGE_PR_VIEW': 'false',
  }, 'nicht lesbar');
  final foreign = m.pr(
    'foreign',
    {'f.dart': 'f\n'},
    extra: {'GIT_AUTHOR_NAME': 'Fremd', 'GIT_AUTHOR_EMAIL': 'f@example.org'},
  );
  _rejects(t, m, 'falsche Identität im PR', args, {
    'MERGE_PR_VIEW': _Repo.view('foreign', foreign),
  }, 'Identität');
  // Unsauberer Baum und lokale, nicht gepushte Commits auf main.
  File('${m.work.path}/a.txt').writeAsStringSync('schmutzig\n');
  _rejects(t, m, 'unsauberer Baum', args, view, 'nicht sauber');
  m.git(['checkout', '--', 'a.txt']);
  m.r.commit('local.txt', 'l\n', cwd: m.work.path);
  _rejects(t, m, 'lokaler Commit auf main', args, view, 'lokales main');
  m.git(['reset', '-q', '--hard', 'origin/main']);
  _conflict(t, m, args);
}

/// origin/main ändert a.txt nach dem Abzweig des PR-Branches ebenfalls.
void _conflict(SelfCheck t, _Repo m, List<String> args) {
  final sha = m.pr('clash', {'a.txt': 'pr\n'});
  m.r.commit('a.txt', 'main\n', cwd: m.work.path);
  m.git(['push', '-q', 'origin', 'main']);
  m.git(['reset', '-q', '--hard', 'HEAD~1']); // lokal hinter origin/main
  _rejects(t, m, 'Konflikt', args, {
    'MERGE_PR_VIEW': _Repo.view('clash', sha),
  }, 'Konflikt');
  t.isTrue(
    !File('${m.common}/MERGE_HEAD').existsSync(),
    'Konflikt: kein offener Merge',
  );
}

void _ciRejections(SelfCheck t, _Repo m) {
  final sha = m.git(['rev-parse', 'feat']);
  final view = {'MERGE_PR_VIEW': _Repo.view('feat', sha)};
  final args = ['7', '--model', _model];
  void ci(String what, String cmd, [String hint = 'CI']) =>
      _rejects(t, m, what, args, {...view, 'MERGE_PR_CI': cmd}, hint);
  const old = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  ci(
    'roter Lauf',
    _ciRuns(['2026-01-01T00:00:00Z $sha feat completed failure']),
  );
  ci(
    'laufender Lauf',
    _ciRuns(['2026-01-01T00:00:00Z $sha feat in_progress ']),
  );
  ci(
    'abgebrochener Lauf',
    _ciRuns(['2026-01-01T00:00:00Z $sha feat completed cancelled']),
  );
  ci('fehlender Lauf', 'true');
  ci('CI-Abfrage schlägt fehl', 'false');
  ci(
    'grüner Lauf nur auf anderem SHA',
    _ciRuns(['2026-01-01T00:00:00Z $old feat completed success']),
  );
  ci(
    'neuester Lauf rot (älterer grün)',
    _ciRuns([
      '2026-01-01T00:00:00Z $sha feat completed success',
      '2026-01-02T00:00:00Z $sha feat completed failure',
    ]),
  );
  _rejects(t, m, 'nur docs-only-Lauf bei Code im Diff', args, {
    ...view,
    'MERGE_PR_CI_MODE': 'echo docs',
  }, 'verkürzt');
  _rejects(t, m, 'CI-Modus nicht ermittelbar', args, {
    ...view,
    'MERGE_PR_CI_MODE': 'false',
  }, 'CI-Modus');
}

void _successes(SelfCheck t, _Repo m) {
  // Reiner Doku-PR: der verkürzte Lauf genügt.
  final docs = m.pr('docs', {'docs/n.md': 'n\n'});
  var res = m.merge(
    ['8', '--model', _model],
    {'MERGE_PR_VIEW': _Repo.view('docs', docs), 'MERGE_PR_CI_MODE': 'false'},
  );
  t.eq(res.exitCode, 0, 'Doku-PR mit verkürztem Lauf: Merge ${res.stderr}');
  m.git(['reset', '-q', '--hard', 'origin/main']);
  m.okFile.deleteSync();

  final sha = m.git(['rev-parse', 'feat']);
  final upstream = m.git(['rev-parse', 'origin/main']);
  res = m.merge(
    ['7', '--model', _model],
    {
      'MERGE_PR_VIEW': _Repo.view('feat', sha, title: 'feat: Neues Werkzeug'),
      'MERGE_PR_CI': _ciRuns([
        '2026-01-02T00:00:00Z $sha feat completed success 2',
        '2026-01-01T00:00:00Z $sha feat completed failure 1',
      ]),
    },
  );
  t.eq(res.exitCode, 0, 'grüner voller Lauf: Merge ${res.stderr}');
  t.eq(
    m.git(['log', '-1', '--format=%B']),
    'Merge #7: feat: Neues Werkzeug\n\n$_trailer',
    'Nachricht „Merge #<pr>: <titel>“ mit genau einem Trailer',
  );
  t.eq(
    m.git(['rev-parse', 'HEAD^1', 'HEAD^2']),
    '$upstream\n$sha',
    'Merge-Commit: Eltern origin/main und PR-Kopf (main zuvor nachgezogen)',
  );
  t.eq(
    m.ok(),
    '${m.git(['rev-parse', 'HEAD^{tree}'])} ${m.head()}\n',
    'Freigabe „<tree> <commit>“ geschrieben',
  );
  t.isTrue(
    '${res.stdout}'.contains('WENDELIN_PUSH_MAIN=1 git push origin main') &&
        m.git(['rev-parse', 'origin/main']) == upstream,
    'Push-Befehl ausgegeben, nicht gepusht',
  );
  _pushThroughHook(t, m);
}

/// Der Merge-Commit des Werkzeugs geht durch den pre-push-Hook; ohne die
/// Freigabe wird derselbe Merge abgelehnt.
void _pushThroughHook(SelfCheck t, _Repo m) {
  final hook = File('tool/hooks/pre-push.sh').absolute.path;
  final line =
      'refs/heads/main ${m.head()} refs/heads/main '
      '${m.git(['rev-parse', 'origin/main'])}';
  int push() => Process.runSync(
    'bash',
    ['-c', 'printf "%s\\n" "\$LINE" | sh "\$HOOK" origin x'],
    workingDirectory: m.work.path,
    environment: {
      ...m.r.env,
      'LINE': line,
      'HOOK': hook,
      'WENDELIN_PUSH_MAIN': '1',
    },
  ).exitCode;
  final ok = m.ok();
  t.eq(push(), 0, 'Merge von merge_pr.sh: pre-push erlaubt');
  m.okFile.writeAsStringSync('');
  t.isTrue(push() != 0, 'derselbe Merge ohne Freigabe: pre-push abgelehnt');
  m.okFile.writeAsStringSync(ok);
}
