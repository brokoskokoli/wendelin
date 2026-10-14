import 'dart:convert';

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
  group('Phala ohne Tools (WP63)', () {
    test('Standard: Tool-Definitionen gehen im Klartext mit', () async {
      final h = TeeHarness();
      await h.provider.chat(_request(tools: [_tool])).toList();
      expect(h.lastExchange!.plainBody['tools'], isNotEmpty);
    });

    test('an: keine Tool-Definitionen, kein tool_choice', () async {
      final h = TeeHarness(noTools: true);
      final events = await h.provider.chat(_request(tools: [_tool])).toList();
      expect(events.last, isA<Done>());
      final body = h.lastExchange!.plainBody;
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
      final raw = h.server.requests
          .firstWhere((r) => r.url.path.endsWith('chat/completions'))
          .body;
      expect(raw, isNot(contains('torch__on')));
      expect(h.provider.caps.tools, isFalse);
    });

    test(
      'an: Tool-Aufrufe und -Ergebnisse aus dem Verlauf bleiben draußen',
      () async {
        final h = TeeHarness(noTools: true);
        final history = [
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
          Message.assistantText('Erledigt.'),
          Message.user('Danke'),
        ];
        await h.provider
            .chat(_request(tools: [_tool], history: history))
            .toList();
        final raw = jsonEncode(h.lastExchange!.plainBody);
        expect(raw, isNot(contains('tool_calls')));
        expect(raw, isNot(contains('torch__on')));
        expect(raw, isNot(contains('"role":"tool"')));
        expect(raw, contains('Erledigt.'));
      },
    );

    test('an: der Agent bekommt eine saubere Textantwort und eine grüne Quittung ohne Tool-Hinweis', () async {
      final h = TeeHarness(noTools: true);
      final request = _request(tools: [_tool]);
      final events = await h.provider.chat(request).toList();
      expect(events.whereType<TextDelta>(), isNotEmpty);
      expect(events.last, isA<Done>());
      final report = await h.provider.reportFor(request);
      expect(report!.status, AttestationStatus.green);
      expect(report.toolsInvolved, isFalse);
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
