import 'dart:convert';

import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Scripted provider of the debug demo mode (no network, no key).
///
/// Understands two requests and answers everything else with a hint:
/// - „Trag mir morgen um 10 Tauchen ein“ → `calendar__create_event`
///   (day: heute/morgen/übermorgen, hour after „um“, title before „ein“),
/// - „Lösch den Termin“ → `calendar__delete_event` for the event created
///   last in the conversation (external, needs confirmation).
///
/// After a tool result it confirms in one sentence. Each answer is played
/// by a [FakeLlmProvider], so streaming and cancellation behave like a
/// real adapter.
final class DemoLlmProvider implements LlmProvider {
  /// Creates the provider; [clock] gives „heute“ for relative days.
  DemoLlmProvider({required this.clock, this.eventDelay = Duration.zero});

  /// Profile id of the demo target.
  static const profileId = 'demo';

  /// Model id of the demo target.
  static const modelId = 'demo-skript';

  /// Time source.
  final Clock clock;

  /// Pause between streamed events (makes streaming visible).
  final Duration eventDelay;

  static const _hint =
      'Im Demo-Modus kann ich Termine eintragen und den letzten wieder '
      'löschen. Probier: „Trag mir morgen um 10 Tauchen ein“.';

  int _calls = 0;

  @override
  ProviderType get type => ProviderType.fake;

  @override
  ProviderCapabilities get caps =>
      const ProviderCapabilities(tools: true, streaming: true);

  @override
  Future<List<ModelInfo>> listModels() async => const [ModelInfo(id: modelId)];

  @override
  Future<HealthCheck> test() async => HealthCheck(
    ok: true,
    latency: Duration.zero,
    message: 'Demo bereit',
    models: const [ModelInfo(id: modelId)],
  );

  @override
  Stream<ChatEvent> chat(ChatRequest req, {CancelToken? cancel}) =>
      FakeLlmProvider([
        turnFor(req.messages),
      ], eventDelay: eventDelay).chat(req, cancel: cancel);

  /// The scripted answer to [messages] (visible for tests).
  ScriptedTurn turnFor(List<Message> messages) {
    final last = messages.isEmpty ? null : messages.last;
    final results = last?.content.whereType<ToolResultBlock>().toList() ?? [];
    if (results.isNotEmpty) return _afterTools(results);
    final text = last?.content.whereType<TextBlock>().map((b) => b.text).join();
    return _plan(text ?? '', messages);
  }

  ScriptedTurn _plan(String text, List<Message> messages) {
    final lower = text.toLowerCase();
    if (lower.contains('lösch')) {
      final id = _lastCreatedEventId(messages);
      if (id == null) {
        return ScriptedTurn.text(
          'Ich habe in diesem Gespräch noch keinen '
          'Termin angelegt, den ich löschen könnte.',
        );
      }
      return _call('calendar__delete_event', {'event_id': id});
    }
    final match = RegExp(
      r'(heute|übermorgen|morgen)?\s*um\s+(\d{1,2})(?::(\d{2}))?\s*(?:uhr\s+)?(.+?)\s+ein\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return ScriptedTurn.text(_hint);
    final days = switch (match[1]?.toLowerCase()) {
      'heute' => 0,
      'übermorgen' => 2,
      _ => 1,
    };
    final now = clock.now();
    final day = DateTime(now.year, now.month, now.day + days);
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      int.parse(match[2]!).clamp(0, 23),
      int.parse(match[3] ?? '0').clamp(0, 59),
    );
    final title = match[4]!.trim();
    return _call('calendar__create_event', {
      'title': title.isEmpty ? 'Termin' : title,
      'start': _localIso(start),
    });
  }

  ScriptedTurn _call(String tool, Map<String, Object?> args) =>
      ScriptedTurn.toolCalls([
        ToolCallBlock(
          id: 'demo_${++_calls}',
          name: tool,
          argumentsJson: jsonEncode(args),
        ),
      ]);

  ScriptedTurn _afterTools(List<ToolResultBlock> results) {
    final r = results.first;
    final text = r.content.whereType<TextBlock>().map((b) => b.text).join();
    if (r.isError) return ScriptedTurn.text('Das hat leider nicht geklappt.');
    if (text.contains(ToolOutcome.declinedText)) {
      return ScriptedTurn.text('Gut, ich lasse alles, wie es ist.');
    }
    if (text.contains('"deleted"')) {
      return ScriptedTurn.text('Erledigt, der Termin ist gelöscht.');
    }
    return ScriptedTurn.text(
      'Erledigt, der Termin steht im Kalender. Du kannst ihn noch kurz '
      'rückgängig machen.',
    );
  }

  /// Id of the event created last, from the tool results in [messages].
  static String? _lastCreatedEventId(List<Message> messages) {
    final pattern = RegExp(r'"created"\s*:\s*\{[^}]*?"id"\s*:\s*"([^"]+)"');
    for (final m in messages.reversed) {
      for (final b in m.content.whereType<ToolResultBlock>()) {
        final text = b.content.whereType<TextBlock>().map((t) => t.text);
        final hit = pattern.allMatches(text.join()).lastOrNull;
        if (hit != null) return hit[1];
      }
    }
    return null;
  }

  static String _localIso(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:'
        '${two(t.minute)}';
  }
}
