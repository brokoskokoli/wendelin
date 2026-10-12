import 'package:flutter/foundation.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'chat_entry.dart';

/// A question the user must answer before the run goes on.
@immutable
sealed class PendingQuestion {
  const PendingQuestion();

  /// Whether it was answered already (the sheet then closes).
  bool get answered;
}

/// Confirmation of an `external` tool call.
final class ToolQuestion extends PendingQuestion {
  /// Creates the question.
  const ToolQuestion(this.event, {required this.request});

  /// The agent event (answer with `respond`).
  final ConfirmationRequired event;

  /// The user's request that led to the call (quoted in the sheet).
  final String request;

  @override
  bool get answered => event.answered;
}

/// Consent to escalate to a provider below the privacy level.
final class EscalationQuestion extends PendingQuestion {
  /// Creates the question.
  const EscalationQuestion(
    this.event, {
    required this.fromName,
    required this.toName,
  });

  /// The agent event (answer with `respond`).
  final EscalationConfirmationRequired event;

  /// Display name of the current provider.
  final String fromName;

  /// Display name of the proposed provider.
  final String toName;

  @override
  bool get answered => event.answered;
}

/// Everything the main screen shows about the conversation.
@immutable
final class ConversationState {
  /// Creates a state.
  ConversationState({
    List<ChatEntry> entries = const [],
    this.running = false,
    this.pending,
    this.activeProfileId,
    this.openTextId,
    this.openThinkingId,
    this.lastRequest,
    this.nextSeq = 1,
  }) : entries = List.unmodifiable(entries);

  /// The empty conversation.
  static final empty = ConversationState();

  /// Entries in display order.
  final List<ChatEntry> entries;

  /// Whether a request is being processed.
  final bool running;

  /// Open confirmation (shown as bottom sheet).
  final PendingQuestion? pending;

  /// Profile of the current model call (from `Routed`/`Escalated`).
  final String? activeProfileId;

  /// Answer text entry of the current model call, if text was streamed.
  final String? openTextId;

  /// Thinking entry of the current model call.
  final String? openThinkingId;

  /// Text of the request being processed.
  final String? lastRequest;

  /// Counter for entry ids.
  final int nextSeq;

  /// A copy with the given fields replaced; `clear…` resets nullable
  /// fields to `null`.
  ConversationState copyWith({
    List<ChatEntry>? entries,
    bool? running,
    PendingQuestion? pending,
    bool clearPending = false,
    String? activeProfileId,
    String? openTextId,
    String? openThinkingId,
    bool clearOpen = false,
    String? lastRequest,
    int? nextSeq,
  }) => ConversationState(
    entries: entries ?? this.entries,
    running: running ?? this.running,
    pending: clearPending ? null : pending ?? this.pending,
    activeProfileId: activeProfileId ?? this.activeProfileId,
    openTextId: clearOpen ? null : openTextId ?? this.openTextId,
    openThinkingId: clearOpen ? null : openThinkingId ?? this.openThinkingId,
    lastRequest: lastRequest ?? this.lastRequest,
    nextSeq: nextSeq ?? this.nextSeq,
  );

  /// The tool entry of [callId], if any.
  ToolEntry? tool(String callId) =>
      entries.whereType<ToolEntry>().where((e) => e.id == callId).firstOrNull;
}
