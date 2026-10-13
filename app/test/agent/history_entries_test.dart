import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/history_entries.dart';
import 'package:wendelin/agent/money.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  final call = ToolCallBlock(
    id: 'c1',
    name: 'web__search',
    argumentsJson: '{"query":"Meer"}',
  );

  test('Verlauf wird zu Einträgen wie im Live-Lauf', () {
    final at = DateTime(2026, 10, 13, 8, 12);
    final entries = entriesFromMessages([
      Message.user('Wie wird das Meer?'),
      Message.assistant([
        const ThinkingBlock('Erst suchen'),
        const TextBlock('Ich schaue nach.'),
        call,
      ]),
      Message.toolResults([
        ToolResultBlock(callId: 'c1', content: const [TextBlock('ok')]),
      ]),
      Message.assistantText('Ruhig.'),
    ], sessionStart: at);
    expect(entries.map((e) => e.runtimeType), [
      SessionStartEntry,
      UserEntry,
      ThinkingEntry,
      AssistantTextEntry,
      ToolEntry,
      AssistantTextEntry,
    ]);
    final tool = entries.whereType<ToolEntry>().single;
    expect(tool.phase, ToolPhase.done);
    expect(tool.undo, UndoPhase.none);
    expect(entries.map((e) => e.id).toSet(), hasLength(entries.length));
  });

  test('ProviderBlock: nie als Text, Zusammenfassung nur als Hinweis', () {
    final entries = entriesFromMessages([
      Message.user('Wetter Nizza?'),
      Message.assistant([
        const ProviderBlock(
          provider: 'anthropic',
          rawJson: '{"type":"server_tool_use","input":{"query":"Nizza"}}',
          summary: 'Websuche: Wetter Nizza',
        ),
        const ProviderBlock(
          provider: 'anthropic',
          rawJson: '{"type":"web_search_tool_result","content":[]}',
        ),
        const TextBlock('Sonnig.'),
      ]),
    ]);
    final notices = entries.whereType<NoticeEntry>().toList();
    expect(notices.single.kind, NoticeKind.providerData);
    expect(notices.single.text, 'Websuche: Wetter Nizza');
    expect(entries.whereType<AssistantTextEntry>().map((e) => e.text), [
      'Sonnig.',
    ]);
    for (final e in entries) {
      final text = switch (e) {
        AssistantTextEntry(:final text) || NoticeEntry(:final text) => text,
        _ => '',
      };
      expect(text, isNot(contains('server_tool_use')));
      expect(text, isNot(contains('web_search_tool_result')));
    }
  });

  test('Ergebnisse setzen Fehler, Ablehnung und Abbruch', () {
    ToolCallBlock c(String id) =>
        ToolCallBlock(id: id, name: 'x__y', argumentsJson: '{}');
    final entries = entriesFromMessages([
      Message.assistant([c('a'), c('b'), c('c')]),
      Message.toolResults([
        ToolOutcome.error('kaputt').toResultBlock('a'),
        ToolOutcome.declined().toResultBlock('b'),
        ToolOutcome.cancelled().toResultBlock('c'),
        ToolOutcome.text('verirrt').toResultBlock('unbekannt'),
      ]),
    ]);
    expect(entries.whereType<ToolEntry>().map((e) => e.phase), [
      ToolPhase.failed,
      ToolPhase.declined,
      ToolPhase.cancelled,
    ]);
  });

  test('ohne Ergebnis bleibt ein Tool laufend; Systemnachrichten fehlen', () {
    final entries = entriesFromMessages([
      Message.system('geheim'),
      Message.assistant([call, const TextBlock('')]),
    ]);
    expect(entries.single, isA<ToolEntry>());
    expect((entries.single as ToolEntry).phase, ToolPhase.running);
  });

  test('formatUsd: Mikro-USD als Cent-Betrag mit Komma', () {
    expect(formatUsd(0), '0,00 \$');
    expect(formatUsd(30000), '0,03 \$');
    expect(formatUsd(4104999), '4,10 \$');
    expect(formatUsd(4105000), '4,11 \$');
    expect(formatUsd(123456789), '123,46 \$');
    expect(formatUsd(-50000), '-0,05 \$');
  });
}
