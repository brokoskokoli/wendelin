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

/// The request was not sent because the GPU check before the request failed
/// (GPU mode „Vorher“, WP52): the user may send it once without the check.
@immutable
final class GpuBlock {
  /// Creates the block.
  const GpuBlock({
    required this.profileId,
    required this.request,
    required this.reason,
    this.noEvidence = false,
  });

  /// The provider delivers no GPU evidence for the model (WP82): nothing to
  /// check, as opposed to a failed check.
  final bool noEvidence;

  /// Provider that was not reached.
  final String profileId;

  /// The request text to send again.
  final String request;

  /// Short German reason (secret-free).
  final String reason;
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
    this.verification,
    this.activeRule,
    this.privateSince,
    this.privateByRequest = false,
    this.gpuBlock,
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

  /// Last receipt check (TEE) of the answering provider, if any.
  final VerificationStatus? verification;

  /// Routing rule that chose the current provider (`Routed.reason`);
  /// `null` = default target or after an escalation.
  final String? activeRule;

  /// Since when the conversation is private: time of its first message
  /// with a privacy floor (a private request, or a run that saw private
  /// content). It stays private until a new conversation starts.
  final DateTime? privateSince;

  /// Whether a request of this conversation was routed privately („privat“
  /// rule); `false` while it is only confidential because a run used the
  /// memory (or other content with a privacy floor).
  final bool privateByRequest;

  /// Request stopped by the GPU check before sending (dialog „Ohne
  /// GPU-Prüfung senden“), or `null`.
  final GpuBlock? gpuBlock;

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
    VerificationStatus? verification,
    bool clearVerification = false,
    String? activeRule,
    bool clearRule = false,
    DateTime? privateSince,
    bool? privateByRequest,
    bool clearPrivate = false,
    GpuBlock? gpuBlock,
    bool clearGpuBlock = false,
  }) => ConversationState(
    entries: entries ?? this.entries,
    running: running ?? this.running,
    pending: clearPending ? null : pending ?? this.pending,
    activeProfileId: activeProfileId ?? this.activeProfileId,
    openTextId: clearOpen ? null : openTextId ?? this.openTextId,
    openThinkingId: clearOpen ? null : openThinkingId ?? this.openThinkingId,
    lastRequest: lastRequest ?? this.lastRequest,
    nextSeq: nextSeq ?? this.nextSeq,
    verification: clearVerification ? null : verification ?? this.verification,
    activeRule: clearRule ? null : activeRule ?? this.activeRule,
    privateSince: clearPrivate ? null : privateSince ?? this.privateSince,
    privateByRequest: clearPrivate
        ? false
        : privateByRequest ?? this.privateByRequest,
    gpuBlock: clearGpuBlock ? null : gpuBlock ?? this.gpuBlock,
  );

  /// The tool entry of [callId], if any.
  ToolEntry? tool(String callId) =>
      entries.whereType<ToolEntry>().where((e) => e.id == callId).firstOrNull;
}
