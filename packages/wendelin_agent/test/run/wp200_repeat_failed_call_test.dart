// WP200: a call that already failed with the same tool and arguments does
// not reach the invoker again (no second confirmation).
import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

/// Invoker that asks for a confirmation per call, counts the calls that reach
/// it and answers with the next of [outcomes] (the last one repeats).
final class CountingInvoker implements ToolInvoker {
  CountingInvoker(this.outcomes);

  final List<ToolOutcome> outcomes;
  final calls = <ToolCallBlock>[];

  @override
  Stream<ToolInvocationEvent> invokeAll(
    List<ToolCallBlock> pending,
    ToolContext ctx,
  ) async* {
    for (final c in pending) {
      final i = calls.length;
      calls.add(c);
      yield ToolStarted(c);
      final q = ConfirmationNeeded(
        c,
        'Frage',
        Completer<bool>(),
        risk: RiskLevel.external,
      );
      yield q;
      await q.decision.future;
      final o = outcomes[i < outcomes.length ? i : outcomes.length - 1];
      yield ToolFinished(c, o, Duration.zero);
    }
  }
}

const _error = '„position“ muss eine Zahl sein.';

({Harness h, CountingInvoker inv, FakeLlmProvider provider, List<int> asked})
_setup(List<String> args, List<ToolOutcome> outcomes) {
  final tool = FakeTool(name: 'ha__set', risk: RiskLevel.external);
  final inv = CountingInvoker(outcomes);
  final (a, provider) = scripted('a', [
    for (var i = 0; i < args.length; i++)
      ScriptedTurn.toolCalls([call('c${i + 1}', 'ha__set', args[i])]),
    ScriptedTurn.text('fertig'),
  ]);
  final h = Harness(primary: a, tools: [tool], invoker: inv);
  return (h: h, inv: inv, provider: provider, asked: <int>[]);
}

Future<List<AgentEvent>> _run(
  Harness h,
  List<int> asked, {
  bool answer = true,
}) => h.run(
  'stell auf 0',
  onEvent: (e) {
    if (e is ConfirmationRequired) {
      asked.add(1);
      e.respond(answer);
    }
  },
);

List<ToolResultBlock> _results(Harness h) => [
  for (final m in h.conversation.messages)
    ...m.content.whereType<ToolResultBlock>(),
];

String _text(ToolResultBlock r) =>
    r.content.whereType<TextBlock>().map((b) => b.text).join(' ');

void main() {
  const same = '{"position":"0"}';

  test('identischer Aufruf nach Fehler: eine Ausführung, eine Bestätigung, '
      'Fehlertext und Hinweis im Ergebnis', () async {
    final s = _setup([same, same], [ToolOutcome.error(_error)]);
    final events = await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(1));
    expect(s.asked, hasLength(1));
    expect(terminal(events), isNot(isA<AgentFailed>()));
    final second = _results(s.h).singleWhere((r) => r.callId == 'c2');
    expect(second.isError, isTrue);
    final text = _text(second);
    expect(text, contains(_error));
    expect(text, contains('bereits fehlgeschlagen'));
    expect(text, contains('Argumente'));
  });

  test('geänderte Argumente laufen normal', () async {
    final s = _setup(
      [same, '{"position":0}'],
      [ToolOutcome.error(_error), ToolOutcome.text('ok')],
    );
    final events = await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(2));
    expect(s.asked, hasLength(2));
    expect(terminal(events), isNot(isA<AgentFailed>()));
  });

  test('2. Wiederholung beendet den Lauf, vor der Ausführung', () async {
    final s = _setup([same, same, same], [ToolOutcome.error(_error)]);
    final events = await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(1));
    expect(s.asked, hasLength(1));
    final failed = terminal(events) as AgentFailed;
    expect(failed.error, AgentErrorKind.repeatedToolError);
    expect(failed.tool, 'ha__set');
    expect(failed.repeats, 3);
    expect(failed.detail, contains(_error));
    // Every call has exactly one result in the history.
    final ids = _results(s.h).map((r) => r.callId).toList();
    expect(ids, ['c1', 'c2', 'c3']);
  });

  test('retryable Fehler (Timeout): gleicher Aufruf läuft erneut, nach 3 '
      'Fehlschlägen Stopp', () async {
    final timeout = ToolOutcome.error('Zeitüberschreitung', retryable: true);
    final s = _setup([same, same, same], [timeout]);
    final events = await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(3));
    expect(s.asked, hasLength(3));
    final failed = terminal(events) as AgentFailed;
    expect(failed.error, AgentErrorKind.repeatedToolError);
    expect(failed.repeats, 3);
  });

  test('retryable Fehler, dann Erfolg: kein Stopp', () async {
    final s = _setup(
      [same, same],
      [
        ToolOutcome.error('Zeitüberschreitung', retryable: true),
        ToolOutcome.text('ok'),
      ],
    );
    final events = await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(2));
    expect(terminal(events), isNot(isA<AgentFailed>()));
  });

  test('abgelehnter Aufruf wird nicht gesperrt', () async {
    final s = _setup(
      [same, same],
      [ToolOutcome.declined(), ToolOutcome.text('ok')],
    );
    await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(2));
    expect(s.asked, hasLength(2));
  });

  test('abgebrochener Aufruf wird nicht gesperrt', () async {
    final s = _setup(
      [same, same],
      [ToolOutcome.cancelled(), ToolOutcome.text('ok')],
    );
    await _run(s.h, s.asked);
    expect(s.inv.calls, hasLength(2));
  });

  test('anderes Werkzeug mit gleichen Argumenten läuft normal', () async {
    final inv = CountingInvoker([ToolOutcome.error(_error)]);
    final (a, _) = scripted('a', [
      ScriptedTurn.toolCalls([call('c1', 'ha__set', same)]),
      ScriptedTurn.toolCalls([call('c2', 'ha__other', same)]),
      ScriptedTurn.text('fertig'),
    ]);
    final h = Harness(
      primary: a,
      tools: [
        FakeTool(name: 'ha__set', risk: RiskLevel.external),
        FakeTool(name: 'ha__other', risk: RiskLevel.external),
      ],
      invoker: inv,
    );
    await _run(h, <int>[]);
    expect(inv.calls, hasLength(2));
  });

  Harness twoTools(CountingInvoker inv, RiskLevel otherRisk) {
    final (a, _) = scripted('a', [
      ScriptedTurn.toolCalls([call('c1', 'ha__set', same)]),
      ScriptedTurn.toolCalls([call('c2', 'ha__make', '{}')]),
      ScriptedTurn.toolCalls([call('c3', 'ha__set', same)]),
      ScriptedTurn.text('fertig'),
    ]);
    return Harness(
      primary: a,
      tools: [
        FakeTool(name: 'ha__set', risk: RiskLevel.external),
        FakeTool(name: 'ha__make', risk: otherRisk),
      ],
      invoker: inv,
    );
  }

  test('Fehlschlag, dann write-Erfolg eines anderen Aufrufs: derselbe Aufruf '
      'läuft erneut', () async {
    final inv = CountingInvoker([
      ToolOutcome.error(_error),
      ToolOutcome.text('angelegt'),
      ToolOutcome.text('ok'),
    ]);
    final events = await _run(twoTools(inv, RiskLevel.write), <int>[]);
    expect(inv.calls.map((c) => c.id), ['c1', 'c2', 'c3']);
    expect(terminal(events), isNot(isA<AgentFailed>()));
  });

  test(
    'Fehlschlag, dann read-Erfolg: derselbe Aufruf bleibt gesperrt',
    () async {
      final inv = CountingInvoker([
        ToolOutcome.error(_error),
        ToolOutcome.text('gelesen'),
        ToolOutcome.text('ok'),
      ]);
      await _run(twoTools(inv, RiskLevel.read), <int>[]);
      expect(inv.calls.map((c) => c.id), ['c1', 'c2']);
    },
  );

  test('nach write-Erfolg zählen Fehlschläge weiter bis zum Stopp', () async {
    final inv = CountingInvoker([
      ToolOutcome.error(_error),
      ToolOutcome.text('angelegt'),
      ToolOutcome.error(_error),
    ]);
    final (a, _) = scripted('a', [
      ScriptedTurn.toolCalls([call('c1', 'ha__set', same)]),
      ScriptedTurn.toolCalls([call('c2', 'ha__make', '{}')]),
      ScriptedTurn.toolCalls([call('c3', 'ha__set', same)]),
      ScriptedTurn.toolCalls([call('c4', 'ha__set', same)]),
      ScriptedTurn.text('fertig'),
    ]);
    final h = Harness(
      primary: a,
      tools: [
        FakeTool(name: 'ha__set', risk: RiskLevel.external),
        FakeTool(name: 'ha__make', risk: RiskLevel.write),
      ],
      invoker: inv,
    );
    final events = await _run(h, <int>[]);
    expect(inv.calls.map((c) => c.id), ['c1', 'c2', 'c3']);
    final failed = terminal(events) as AgentFailed;
    expect(failed.error, AgentErrorKind.repeatedToolError);
  });
}
