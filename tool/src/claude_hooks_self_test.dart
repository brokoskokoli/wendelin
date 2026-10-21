// Selbsttests der Claude-Code-Hooks (tool/hooks/claude/, WP110) und der
// Emulator-Sperre (tool/emulator_lock.sh). Alles in temporären Ordnern.
import 'dart:convert';
import 'dart:io';

import 'budget_self_test.dart';
import 'emulator_boot_self_test.dart';
import 'emulator_lock_self_test.dart';
import 'sandbox.dart';
import 'self_check.dart';

Future<void> claudeHooksChecks(SelfCheck t) async {
  _bashGuard(t);
  budgetChecks(t);
  _settings(t);
  await emulatorLockChecks(t);
  await emulatorBootChecks(t);
}

const hooksDir = 'tool/hooks/claude';

ProcessResult runHook(
  String script,
  List<String> args,
  Map<String, Object?> input,
  Map<String, String> env,
) => Process.runSync(
  'sh',
  ['-c', 'printf "%s" "\$INPUT" | python3 "\$SCRIPT" "\$@"', 'sh', ...args],
  environment: {
    ...env,
    'INPUT': jsonEncode(input),
    'SCRIPT': File('$hooksDir/$script').absolute.path,
    'PYTHONDONTWRITEBYTECODE': '1',
  },
);

const _denied = [
  // --no-verify
  'git commit --no-verify -m x',
  'git commit -m x --no-verify',
  'git push --no-verify origin wp/1-x',
  'git commit -nm x',
  'git commit -n -m x',
  'git commit -an',
  'git merge --no-verify x',
  // push auf main
  'git push origin main',
  'git push origin +main',
  'git push origin HEAD:main',
  'git push origin wp/1-x:main',
  'git push origin HEAD:refs/heads/main',
  'git push origin refs/heads/main',
  'git push origin :main',
  'git push --force origin main',
  'git push -u origin main',
  'git push --all origin',
  'git push --mirror',
  'git -C ../x push origin main',
  'git -c push.default=current push origin main',
  'cd x && git push origin main',
  'git status; git push origin main',
  'git add -A && git commit -m a || git push origin main',
  'echo x | git push origin main',
  'true & git push origin main',
  '"git" push "origin" "main"',
  "'git' push origin 'HEAD:main'",
  r'git push origin ma\in',
  '/usr/bin/git push origin main',
  'env git push origin main',
  'command git push origin main',
  'sudo git push origin main',
  'env -i git push origin main',
  'bash -c "git push origin main"',
  "sh -c 'git push origin HEAD:main'",
  'eval "git push origin main"',
  'xargs git push origin main',
  'WENDELIN_PUSH_MAIN=0 git push origin main',
  'FOO=1 git push origin main',
  '(git push origin main)',
  'git push origin main # WENDELIN_PUSH_MAIN=1',
  'echo WENDELIN_PUSH_MAIN=1; git push origin main',
  // Schlüsselwörter und Wrapper mit Optionswerten
  'if git push origin main; then echo ok; fi',
  'if true; then git push origin main; fi',
  'if false; then :; elif git push origin main; then :; fi',
  'if true; then :; else git push origin main; fi',
  'while pkill foo; do sleep 1; done',
  'until git commit --no-verify -m x; do :; done',
  'for i in 1 2; do git push origin main; done',
  '! git commit --no-verify -m x',
  '{ git push origin HEAD:main; }',
  'f() { git push origin main; }; f',
  'timeout 5 git push origin main',
  'timeout -k 1 5 git push origin main',
  'nice -n 5 git push origin main',
  'sudo -u root git push origin main',
  'nohup git push origin main',
  'xargs -n1 git push origin main',
  'find . -exec git push origin main \\;',
  'find . -name x -exec pkill foo {} +',
  'timeout 5 pkill foo',
  'stdbuf -oL git push origin main',
  'chrt 1 git push origin main',
  'taskset -c 0 git push origin main',
  // abgekürzte Langoptionen, heads/main
  'git commit --no-veri -m x',
  'git commit --no-v -m x',
  'git push --no-ver origin wp/1-x',
  'git push origin HEAD:heads/main',
  'git push origin heads/main',
  // Prozesse
  "cat <<'EOF' > x\nhallo\nEOF\ngit push origin main",
  'pkill emulator',
  'killall adb',
  'cd x && pkill -f foo',
  'sudo pkill foo',
  '/usr/bin/killall foo',
  'bash -c "pkill foo"',
  // Identität
  'git -c user.name=x commit -m y',
  'git -c user.email=a@b commit -m y',
  'git -c core.hooksPath=/dev/null commit -m y',
  'git -c USER.NAME=x commit -m y',
  'git --config-env=user.name=NAME commit -m y',
  'git config user.name x',
  'git config --global user.email a@b',
  'git config core.hooksPath /dev/null',
  'GIT_AUTHOR_NAME=x git commit -m y',
  'GIT_COMMITTER_EMAIL=a@b git commit -m y',
  'env GIT_AUTHOR_EMAIL=a@b git commit -m y',
  'export GIT_COMMITTER_NAME=x',
  'export FOO=1 GIT_AUTHOR_NAME=x',
  'a=1 GIT_AUTHOR_DATE=x git commit -m y',
  'bash -c "GIT_AUTHOR_NAME=x git commit -m y"',
];

const _allowed = [
  'git push origin wp/110-agent-guardrails-ci',
  'git push -u origin wp/110-agent-guardrails-ci',
  'git push origin HEAD:wp/110-x',
  'git push origin +wp/110-x',
  'git push --force-with-lease origin wp/110-x',
  'git push', // auf einem wp/*-Branch
  'git push origin HEAD', // auf einem wp/*-Branch
  'git push origin :wp/110-old',
  'git push origin domain',
  'git push origin feature/main-menu',
  'git commit -m "feat: x"',
  'git commit -am "fix"',
  'git commit -m "Hook sperrt --no-verify und git push origin main"',
  'git commit -m "mit -n und pkill im Text"',
  'git commit -m "GIT_AUTHOR_NAME=x im Text"',
  'git commit --amend --no-edit',
  'git commit -m "\$(cat <<\'EOF\'\ngit push origin main --no-verify\nEOF\n)"',
  "cat >> f <<'EOF'\npkill x\nGIT_AUTHOR_NAME=x git push origin main\nEOF",
  'git add -A && git commit -m x',
  'git status && git log --oneline | head',
  'git pull --no-rebase origin main',
  'git fetch origin main',
  'git merge origin/main',
  'git checkout main',
  'git diff main',
  'git config user.name',
  'git config --get user.email',
  'git config pull.rebase false',
  'git -C ../x status',
  'tool/merge_wp.sh wp/110-agent-guardrails-ci',
  'tool/ci_wait.sh wp/110-agent-guardrails-ci',
  'WENDELIN_PUSH_MAIN=1 git push origin main',
  'WENDELIN_PUSH_MAIN=1 git push origin HEAD:main',
  'env WENDELIN_PUSH_MAIN=1 git push origin main',
  'export WENDELIN_PUSH_MAIN=1; git push origin main',
  'WENDELIN_PUSH_MAIN=1; git push origin main',
  'cd x && WENDELIN_PUSH_MAIN=1 git push origin main',
  'bash -c "WENDELIN_PUSH_MAIN=1 git push origin main"',
  'git commit -m "docs(status): x" && WENDELIN_PUSH_MAIN=1 git push origin main',
  'dart run tool/gate.dart --changed',
  'tool/t.sh packages/wendelin_core/test/a_test.dart --name "x"',
  'ls; echo "kill the process"; kill 123',
  'echo pkill',
  'if git status; then echo ok; fi',
  'while read x; do echo \$x; done',
  'timeout 5 git status',
  'nice -n 5 git log',
  'stdbuf -oL ls',
  'taskset -c 0 ls',
  'sudo -u root ls',
  'xargs -n1 echo',
  'find . -name x -exec echo {} \\;',
  'git commit -m x --no-edit',
  'git push origin wp/1-x:heads/main-x',
  'timeout 5 env WENDELIN_PUSH_MAIN=1 git push origin main',
  '',
];

void _bashGuard(SelfCheck t) {
  t.group('Claude-Hook bash_guard');
  final dir = Directory.systemTemp.createTempSync('bashguard_selftest_');
  try {
    final onMain = Sandbox(Directory('${dir.path}/m')..createSync());
    onMain.git(['init', '-q', '-b', 'main']);
    onMain.commit('a.txt', 'a\n');
    final onWp = Sandbox(Directory('${dir.path}/w')..createSync());
    onWp.git(['init', '-q', '-b', 'wp/1-x']);
    onWp.commit('a.txt', 'a\n');

    int code(String cmd, {Sandbox? at}) => runHook('bash_guard.py', [], {
      'tool_name': 'Bash',
      'tool_input': {'command': cmd},
      'cwd': (at ?? onWp).dir.path,
    }, {}).exitCode;

    for (final c in _denied) {
      t.eq(code(c), 2, 'abgelehnt: $c');
    }
    // `git push` ohne Ziel pusht den aktuellen Branch.
    t.eq(
      code('git push', at: onMain),
      2,
      'abgelehnt: git push auf Branch main',
    );
    t.eq(
      code('git push origin', at: onMain),
      2,
      'abgelehnt: git push origin auf main',
    );
    t.eq(
      code('git push origin HEAD', at: onMain),
      2,
      'abgelehnt: push HEAD auf main',
    );
    t.eq(
      code('git push -u origin HEAD', at: onMain),
      2,
      'abgelehnt: push -u HEAD auf main',
    );

    for (final c in _allowed) {
      t.eq(code(c), 0, 'erlaubt: ${c.replaceAll('\n', r'\n')}');
    }
    t.eq(
      code('git push origin HEAD', at: onMain) == 2,
      true,
      'HEAD auf main abgelehnt',
    );
    // Fail-open bei unlesbarer Eingabe.
    t.eq(
      Process.runSync('sh', [
        '-c',
        'echo kaputt | python3 $hooksDir/bash_guard.py',
      ]).exitCode,
      0,
      'kaputtes JSON: durchlassen',
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

/// `.claude/settings.json` trägt genau die getesteten Hooks.
void _settings(SelfCheck t) {
  t.group('Claude-Hook settings.json');
  final f = File('.claude/settings.json');
  if (!f.existsSync()) {
    t.isTrue(false, '.claude/settings.json fehlt');
    return;
  }
  final hooks = (jsonDecode(f.readAsStringSync()) as Map)['hooks'] as Map;
  String cmd(String event, String matcher) {
    for (final e in (hooks[event] as List).cast<Map<String, Object?>>()) {
      if (e['matcher'] == matcher) {
        return ((e['hooks'] as List).first as Map)['command'] as String;
      }
    }
    return '';
  }

  t.isTrue(
    cmd('PreToolUse', 'Bash').endsWith('/$hooksDir/bash_guard.py'),
    'PreToolUse Bash -> bash_guard.py',
  );
  t.isTrue(
    cmd('PreToolUse', '*').endsWith('/$hooksDir/budget.py pre'),
    'PreToolUse * -> budget.py pre',
  );
  t.isTrue(
    cmd('PostToolUse', '*').endsWith('/$hooksDir/budget.py post'),
    'PostToolUse * -> budget.py post',
  );
  for (final s in ['bash_guard.py', 'budget.py']) {
    t.isTrue(
      File('$hooksDir/$s').statSync().mode & 0x40 != 0,
      '$s ist ausführbar',
    );
  }
}
