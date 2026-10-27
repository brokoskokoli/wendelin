// WP163 B: a tool outcome that ends the run stops the agent before the next
// model request, whatever the listener does meanwhile.
import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  test(
    'Ergebnis mit endsRun: genau ein Modellaufruf, Lauf endet abgebrochen',
    () async {
      final tool = FakeTool(
        name: 'maps__navigate',
        outcome: ToolOutcome.error(
          'Nur entsperrt',
          summary: 'x',
          endsRun: true,
        ),
      );
      final (a, provider) = scripted('a', [
        ScriptedTurn.toolCalls([call('c1', 'maps__navigate', '{}')]),
        ScriptedTurn.text('darf nicht kommen'),
      ]);
      final h = Harness(primary: a, tools: [tool]);
      final events = await h.run('navigiere');
      expect(provider.requests.length, 1);
      expect(tool.callCount, 1);
      final end = terminal(events) as AgentFailed;
      expect(end.error, AgentErrorKind.cancelled);
    },
  );

  test('Fehler ohne endsRun: das Modell wird weiter gefragt', () async {
    final tool = FakeTool(
      name: 'maps__navigate',
      outcome: ToolOutcome.error('kaputt'),
    );
    final (a, provider) = scripted('a', [
      ScriptedTurn.toolCalls([call('c1', 'maps__navigate', '{}')]),
      ScriptedTurn.text('sorry'),
    ]);
    final h = Harness(primary: a, tools: [tool]);
    await h.run('navigiere');
    expect(provider.requests.length, 2);
  });
}
