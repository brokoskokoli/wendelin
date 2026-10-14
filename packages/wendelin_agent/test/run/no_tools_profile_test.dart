// WP63: a profile without tools gets no tool definitions, the history as
// text, and a note in the system prompt.

import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support.dart';

void main() {
  test(
    'Profil ohne Tools: keine Tools, Verlauf als Text, Hinweis im Prompt',
    () async {
      final provider = FakeLlmProvider([
        ScriptedTurn.text('Okay.'),
      ], caps: const ProviderCapabilities(tools: false, streaming: true));
      final target = ProviderTarget(
        profileId: 'phala',
        modelId: 'm',
        provider: provider,
        privacy: PrivacyLevel.standard,
      );
      final h = Harness(
        primary: target,
        tools: [FakeTool(name: 'cal__create', outcome: ToolOutcome.text('x'))],
        history: [
          Message.user('Trag Tauchen ein'),
          Message.assistant([call('c1', 'cal__create', '{"title":"Tauchen"}')]),
          Message.toolResults([
            ToolResultBlock(
              callId: 'c1',
              content: const [TextBlock('angelegt')],
            ),
          ]),
          Message.assistantText('Erledigt.'),
        ],
      );
      await h.run('Danke');
      final req = provider.requests.single;
      expect(req.tools, isEmpty);
      expect(req.systemPrompt, contains(AgentRunnerTexts.noToolsNote));
      final texts = req.messages
          .expand((m) => m.content)
          .whereType<TextBlock>()
          .map((t) => t.text)
          .join('\n');
      expect(texts, contains('[Tool-Aufruf: cal__create'));
      expect(texts, contains('[Tool-Ergebnis: angelegt]'));
      expect(
        req.messages.expand((m) => m.content).whereType<ToolCallBlock>(),
        isEmpty,
      );
    },
  );

  test('Profil mit Tools: unverändert, kein Hinweis', () async {
    final (a, provider) = scripted('a', [ScriptedTurn.text('Hi')]);
    final h = Harness(
      primary: a,
      tools: [FakeTool(name: 'cal__create', outcome: ToolOutcome.text('x'))],
    );
    await h.run('Hallo');
    final req = provider.requests.single;
    expect(req.tools, isNotEmpty);
    expect(req.systemPrompt, isNot(contains(AgentRunnerTexts.noToolsNote)));
  });
}
