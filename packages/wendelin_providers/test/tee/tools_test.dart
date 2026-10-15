import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'provider_harness.dart';

const _tool = ToolSpec(
  name: 'torch__on',
  description: 'Schaltet die Taschenlampe ein.',
  inputSchema: {'type': 'object', 'properties': <String, Object?>{}},
);

ChatRequest _request({
  List<ToolSpec> tools = const [],
  List<Message>? history,
}) => ChatRequest(
  systemPrompt: 'Du bist ein Testassistent.',
  messages: history ?? [Message.user('Hallo')],
  model: 'm',
  maxTokens: 50,
  tools: tools,
);

void main() {
  group('Phala mit Tools (WP71)', () {
    test('Standard: Tool-Definitionen gehen im Klartext mit', () async {
      final h = TeeHarness();
      await h.provider.chat(_request(tools: [_tool])).toList();
      expect(h.lastExchange!.plainBody['tools'], isNotEmpty);
    });

    test('Quittung meldet toolsInvolved, wenn Tools gesendet wurden', () async {
      final h = TeeHarness();
      final request = _request(tools: [_tool]);
      await h.provider.chat(request).toList();
      expect((await h.provider.reportFor(request))!.toolsInvolved, isTrue);
    });

    test('Quittung meldet toolsInvolved bei empfangenem Tool-Aufruf', () async {
      final h = TeeHarness(chatFixture: 'openai/tool_call.sse');
      final request = _request();
      final events = await h.provider.chat(request).toList();
      expect(events.whereType<ToolCallComplete>(), isNotEmpty);
      expect((await h.provider.reportFor(request))!.toolsInvolved, isTrue);
    });

    test('ohne Tools und ohne Aufrufe: kein Hinweis', () async {
      final h = TeeHarness();
      final request = _request();
      await h.provider.chat(request).toList();
      expect((await h.provider.reportFor(request))!.toolsInvolved, isFalse);
    });

    test(
      'Tool-Verlauf im gesendeten Request zählt als Tool-Beteiligung',
      () async {
        final h = TeeHarness();
        final request = _request(
          history: [
            Message.user('Licht an'),
            Message.assistant([
              const ToolCallBlock(
                id: 'c1',
                name: 'torch__on',
                argumentsJson: '{}',
              ),
            ]),
            Message.toolResults([
              ToolResultBlock(callId: 'c1', content: const [TextBlock('ok')]),
            ]),
            Message.user('Danke'),
          ],
        );
        await h.provider.chat(request).toList();
        expect((await h.provider.reportFor(request))!.toolsInvolved, isTrue);
      },
    );

    test('gelber Zwischenbericht trägt toolsInvolved mit', () async {
      final h = TeeHarness()..receiptFailures = 1;
      final seen = <AttestationReport>[];
      h.provider.reports.listen(seen.add);
      await h.provider.chat(_request(tools: [_tool])).toList();
      await h.provider.pendingReport();
      await pumpEventQueue();
      final yellow = seen.firstWhere(
        (r) => r.status == AttestationStatus.yellow,
      );
      expect(yellow.toolsInvolved, isTrue);
    });
  });
}
