import 'package:wendelin_core/wendelin_core.dart';

import 'chat_entry.dart';
import 'conversation_reducer.dart';

/// Conversation entries for stored [messages] of a session (restore after
/// an app restart).
///
/// Text and tool calls are shown as in a live run, without undo (the undo
/// actions are gone). Thinking becomes a [ThinkingEntry] (hidden unless
/// enabled). A [ProviderBlock] is never shown as text: only its `summary`
/// appears as a small [NoticeKind.providerData] hint, a block without
/// summary is not shown at all.
List<ChatEntry> entriesFromMessages(
  List<Message> messages, {
  DateTime? sessionStart,
}) {
  final out = <ChatEntry>[];
  var seq = 0;
  String id() => 'h${++seq}';
  if (sessionStart != null) out.add(SessionStartEntry(id(), sessionStart));
  for (final m in messages) {
    switch (m.role) {
      case Role.user:
        final text = m.text;
        if (text.isNotEmpty) out.add(UserEntry(id(), text));
        _applyResults(out, m);
      case Role.tool:
        _applyResults(out, m);
      case Role.assistant:
        for (final block in m.content) {
          switch (block) {
            case TextBlock(:final text) when text.isNotEmpty:
              out.add(AssistantTextEntry(id(), text));
            case ThinkingBlock(:final text) when text.isNotEmpty:
              out.add(ThinkingEntry(id(), text));
            case ToolCallBlock(id: final callId, :final name):
              out.add(ToolEntry(callId, toolName: name));
            case ProviderBlock(:final summary?):
              out.add(NoticeEntry(id(), NoticeKind.providerData, summary));
            case TextBlock() ||
                ThinkingBlock() ||
                ProviderBlock() ||
                ImageBlock() ||
                ToolResultBlock():
            // Empty text, redacted thinking, provider data without summary,
            // images and stray results are not shown.
          }
        }
      case Role.system:
      // Never part of the visible conversation.
    }
  }
  return out;
}

void _applyResults(List<ChatEntry> out, Message m) {
  for (final r in m.content.whereType<ToolResultBlock>()) {
    final i = out.indexWhere((e) => e is ToolEntry && e.id == r.callId);
    if (i < 0) continue;
    final phase = ConversationReducer.phaseOf(
      ToolOutcome(content: r.content, isError: r.isError),
    );
    out[i] = (out[i] as ToolEntry).copyWith(phase: phase);
  }
}
