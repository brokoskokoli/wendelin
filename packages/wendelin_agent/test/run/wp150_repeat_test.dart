// WP150 diagnosis: the model repeats the same failing call (new call ids).
import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  test('dreimal derselbe Aufruf mit demselben Fehler beendet den Lauf mit dem Fehler', () async {
    final tool = FakeTool(
      name: 'ha__call',
      outcome: ToolOutcome.error('„Annas Licht“ ist gerade nicht erreichbar.'),
    );
    final (a, provider) = scripted('a', [
      for (var i = 1; i <= 9; i++)
        ScriptedTurn.toolCalls([
          call(
            'c$i',
            'ha__call',
            '{"entity":"Annas Licht","service":"turn_on"}',
          ),
        ]),
      ScriptedTurn.text('nie erreicht'),
    ]);
    final h = Harness(primary: a, tools: [tool]);
    final events = await h.run('Annas Licht an');
    final end = terminal(events);
    // Desired: stop after the 2nd repetition with an own, understandable text.
    expect(tool.callCount, 3);
    expect(provider.requests.length, 3);
    final failed = end as AgentFailed;
    expect(failed.error, AgentErrorKind.repeatedToolError);
    // No technical detail for the user; tool, error and count for the log.
    expect(
      failed.message,
      'Das hat gerade nicht geklappt, es gab einen '
      'technischen Fehler.',
    );
    expect(failed.tool, 'ha__call');
    expect(failed.repeats, 3);
    expect(failed.detail, contains('ist gerade nicht erreichbar'));
  });

  test('derselbe Aufruf, der gelingt, wird nicht abgebrochen', () async {
    final tool = FakeTool(name: 'ha__call', outcome: ToolOutcome.text('ok'));
    final (a, _) = scripted('a', [
      for (var i = 1; i <= 5; i++)
        ScriptedTurn.toolCalls([call('c$i', 'ha__call', '{"e":"x"}')]),
      ScriptedTurn.text('fertig'),
    ]);
    final h = Harness(primary: a, tools: [tool]);
    final end = terminal(await h.run('mehrfach'));
    expect(end, isNot(isA<AgentFailed>()));
    expect(tool.callCount, 5);
  });

  test(
    'derselbe Fehler mit unterschiedlichen Argumenten bricht nicht ab',
    () async {
      final tool = FakeTool(
        name: 'ha__call',
        outcome: ToolOutcome.error('nicht erreichbar'),
      );
      final (a, _) = scripted('a', [
        for (var i = 1; i <= 5; i++)
          ScriptedTurn.toolCalls([call('c$i', 'ha__call', '{"e":"x$i"}')]),
        ScriptedTurn.text('gebe auf'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final end = terminal(await h.run('viele'));
      expect(end, isNot(isA<AgentFailed>()));
      expect(tool.callCount, 5);
    },
  );

  test('zwei Fehlschläge desselben Aufrufs reichen noch nicht', () async {
    final tool = FakeTool(
      name: 'ha__call',
      outcome: ToolOutcome.error('nicht erreichbar'),
    );
    final (a, _) = scripted('a', [
      for (var i = 1; i <= 2; i++)
        ScriptedTurn.toolCalls([call('c$i', 'ha__call', '{"e":"x"}')]),
      ScriptedTurn.text('gebe auf'),
    ]);
    final h = Harness(primary: a, tools: [tool]);
    final end = terminal(await h.run('zweimal'));
    expect(end, isNot(isA<AgentFailed>()));
  });

  test(
    'drei gleiche Fehlaufrufe in einer Runde zählen einzeln (gewollt)',
    () async {
      final tool = FakeTool(
        name: 'ha__call',
        outcome: ToolOutcome.error('nicht erreichbar'),
      );
      final (a, _) = scripted('a', [
        ScriptedTurn.toolCalls([
          for (var i = 1; i <= 3; i++) call('c$i', 'ha__call', '{"e":"x"}'),
        ]),
        ScriptedTurn.text('nie erreicht'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final end = terminal(await h.run('parallel'));
      expect((end as AgentFailed).error, AgentErrorKind.repeatedToolError);
    },
  );
}
