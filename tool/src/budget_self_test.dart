// Selbsttests von tool/hooks/claude/budget.py (WP110): Schwellen 60/90,
// Zählschlüssel, Ausnahmen.
import 'dart:convert';
import 'dart:io';

import 'claude_hooks_self_test.dart';
import 'self_check.dart';

void budgetChecks(SelfCheck t) {
  t.group('Claude-Hook budget');
  final dir = Directory.systemTemp.createTempSync('budget_selftest_');
  try {
    final b = _Budget(t, dir.path);
    final a1 = b.input('Read', agent: 'a1');
    b.thresholds(a1);
    b.afterBlock(a1);
    b.keys(a1);
    b.exemptions(a1);
    t.isTrue(
      Directory('${dir.path}/counters').listSync().isNotEmpty,
      'Zähler im WENDELIN_HOOK_DIR (außerhalb des Repos)',
    );
  } finally {
    dir.deleteSync(recursive: true);
  }
}

typedef _In = Map<String, Object?>;

final class _Budget {
  _Budget(this.t, String dir)
    : base = {
        'WENDELIN_HOOK_DIR': '$dir/counters',
        'CLAUDE_PROJECT_DIR': '/home/x/james-wt/wp1',
      };

  final SelfCheck t;
  final Map<String, String> base;

  _In input(String tool, {String? agent, String? type, String command = ''}) =>
      {
        'tool_name': tool,
        'agent_id': ?agent,
        'agent_type': ?type,
        'transcript_path': '/t/main.jsonl',
        'session_id': 's1',
        'cwd': '/home/x/james-wt/wp1',
        'tool_input': {if (command.isNotEmpty) 'command': command},
      };

  ProcessResult post(_In i, [Map<String, String> env = const {}]) =>
      runHook('budget.py', ['post'], i, {...base, ...env});

  int pre(_In i, [Map<String, String> env = const {}]) =>
      runHook('budget.py', ['pre'], i, {...base, ...env}).exitCode;

  String ctx(ProcessResult r) {
    final o = (r.stdout as String).trim();
    if (o.isEmpty) return '';
    final h =
        (jsonDecode(o) as Map<String, Object?>)['hookSpecificOutput']
            as Map<String, Object?>;
    return '${h['hookEventName']}|${h['additionalContext']}';
  }

  /// Warnung ab dem 60., Sperre ab dem 91. Aufruf (90 gezählt).
  void thresholds(_In a1) {
    for (var n = 1; n <= 89; n++) {
      final c = ctx(post(a1));
      if (n == 59) t.eq(c, '', 'Aufruf 59 ohne Hinweis');
      if (n == 60) {
        t.isTrue(
          c.startsWith('PostToolUse|') && c.contains('übergeben'),
          'Aufruf 60 liefert additionalContext zur Übergabe: $c',
        );
      }
      if (n == 61) t.isTrue(c.contains('61'), 'Hinweis bleibt ab 60 bestehen');
    }
    t.eq(pre(a1), 0, '89 gezählt: noch erlaubt');
    post(a1);
  }

  void afterBlock(_In a1) {
    t.eq(pre(a1), 2, 'ab 90: Read blockiert');
    t.eq(pre(input('Grep', agent: 'a1')), 2, 'ab 90: Grep blockiert');
    t.eq(pre(input('Agent', agent: 'a1')), 2, 'ab 90: Agent blockiert');
    t.eq(pre(input('Write', agent: 'a1')), 0, 'ab 90: Write erlaubt');
    t.eq(pre(input('Edit', agent: 'a1')), 0, 'ab 90: Edit erlaubt');
    const ok = [
      'git commit -m "WIP"',
      'git add -A && git commit -m "WIP"',
      'git status',
      'git -C /x commit -m w',
    ];
    const bad = [
      'ls',
      'git push origin wp/1-x',
      'git log',
      'git commit -m x; rm -rf y',
      'git commit -m x && dart test',
      'echo git commit',
      '',
    ];
    for (final c in ok) {
      t.eq(
        pre(input('Bash', agent: 'a1', command: c)),
        0,
        'ab 90: erlaubt: $c',
      );
    }
    for (final c in bad) {
      t.eq(
        pre(input('Bash', agent: 'a1', command: c)),
        2,
        'ab 90: blockiert: $c',
      );
    }
  }

  /// Zählschlüssel: agent_id; Sitzungen ohne agent_id zählen und sperren nie.
  void keys(_In a1) {
    t.eq(pre(input('Read', agent: 'a2')), 0, 'anderer Agent zählt separat');
    const one = {'WENDELIN_CALL_BLOCK': '1'};
    for (var n = 0; n < 3; n++) {
      t.eq(ctx(post(input('Read'))), '', 'ohne agent_id: kein Hinweis');
    }
    t.eq(pre(input('Read'), one), 0, 'ohne agent_id: nie gesperrt');
  }

  /// Orchestrator im Haupt-Checkout, Reviewer, Abschalter.
  void exemptions(_In a1) {
    const main = {'CLAUDE_PROJECT_DIR': '/home/x/wendelin'};
    t.eq(ctx(post(a1, main)), '', 'Haupt-Checkout: nicht gezählt');
    t.eq(
      pre(a1, {...main, 'WENDELIN_CALL_BLOCK': '1'}),
      0,
      'Haupt-Checkout: nie gesperrt',
    );
    final rev = input('Read', agent: 'a1', type: 'wendelin-reviewer');
    t.eq(pre(rev), 2, 'Reviewer (agent_id) zählt wie jeder Sub-Agent');
    t.eq(
      pre(a1, {'WENDELIN_CALL_LIMIT': '0'}),
      0,
      'WENDELIN_CALL_LIMIT=0 schaltet ab',
    );
    t.eq(
      pre(a1, {...main, 'WENDELIN_CALL_LIMIT': '1'}),
      2,
      'WENDELIN_CALL_LIMIT=1 erzwingt auch im Haupt-Checkout',
    );
  }
}
