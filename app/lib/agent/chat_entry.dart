import 'package:flutter/foundation.dart';

/// One item of the conversation shown on the main screen.
@immutable
sealed class ChatEntry {
  const ChatEntry(this.id);

  /// Stable id within the conversation (keys, updates).
  final String id;
}

/// Start of a session („Heute · 08:12“).
final class SessionStartEntry extends ChatEntry {
  /// Creates the entry.
  const SessionStartEntry(super.id, this.at);

  /// When the session started.
  final DateTime at;
}

/// A request of the user.
final class UserEntry extends ChatEntry {
  /// Creates the entry.
  const UserEntry(super.id, this.text);

  /// What the user wrote or said.
  final String text;
}

/// Answer text of one model call (streamed; may be discarded by
/// `AgentTextReset`).
final class AssistantTextEntry extends ChatEntry {
  /// Creates the entry.
  const AssistantTextEntry(super.id, this.text);

  /// Text so far.
  final String text;

  /// A copy with [more] appended.
  AssistantTextEntry append(String more) => AssistantTextEntry(id, text + more);
}

/// Reasoning text of the model (display only, hidden unless enabled).
final class ThinkingEntry extends ChatEntry {
  /// Creates the entry.
  const ThinkingEntry(super.id, this.text);

  /// Text so far.
  final String text;

  /// A copy with [more] appended.
  ThinkingEntry append(String more) => ThinkingEntry(id, text + more);
}

/// Phase of a tool call.
enum ToolPhase {
  /// Running (or waiting for its turn).
  running,

  /// Waiting for the user's confirmation.
  awaitingConfirmation,

  /// Finished successfully.
  done,

  /// Finished with an error.
  failed,

  /// The user declined.
  declined,

  /// The run was cancelled before it finished.
  cancelled,
}

/// State of the undo offer of a tool call.
enum UndoPhase {
  /// No undo offered.
  none,

  /// Can be undone ([ToolEntry.undoRemaining] left).
  pending,

  /// Undo is running.
  running,

  /// Was undone.
  undone,

  /// Window passed.
  expired,

  /// Undo failed.
  failed,
}

/// A tool call (chip, or result card while it can be undone).
final class ToolEntry extends ChatEntry {
  /// Creates the entry; [id] is the call id.
  const ToolEntry(
    super.id, {
    required this.toolName,
    this.phase = ToolPhase.running,
    this.summary,
    this.undoLabel,
    this.undo = UndoPhase.none,
    this.undoRemaining = Duration.zero,
  });

  /// `integration__action`.
  final String toolName;

  /// Where the call is.
  final ToolPhase phase;

  /// Short result text for the card („Termin angelegt: Tauchen, …“).
  final String? summary;

  /// Label of the undo action („Termin entfernen“).
  final String? undoLabel;

  /// Undo state.
  final UndoPhase undo;

  /// Time left to undo (only while [undo] is pending).
  final Duration undoRemaining;

  /// Integration id (prefix before `__`).
  String get integrationId {
    final i = toolName.indexOf('__');
    return i < 0 ? toolName : toolName.substring(0, i);
  }

  /// A copy with the given fields replaced.
  ToolEntry copyWith({
    ToolPhase? phase,
    String? summary,
    String? undoLabel,
    UndoPhase? undo,
    Duration? undoRemaining,
  }) => ToolEntry(
    id,
    toolName: toolName,
    phase: phase ?? this.phase,
    summary: summary ?? this.summary,
    undoLabel: undoLabel ?? this.undoLabel,
    undo: undo ?? this.undo,
    undoRemaining: undoRemaining ?? this.undoRemaining,
  );
}

/// The request was handed to another provider.
final class EscalationEntry extends ChatEntry {
  /// Creates the entry.
  const EscalationEntry(super.id, this.label);

  /// „an Claude Sonnet übergeben“.
  final String label;
}

/// Kind of a [NoticeEntry].
enum NoticeKind {
  /// Neutral information (e.g. cancelled).
  info,

  /// Warning (e.g. budget threshold reached).
  warning,

  /// The request failed.
  error,

  /// Provider-specific content (e.g. server-side web search): only its
  /// summary is shown, never as answer text.
  providerData,
}

/// A small hint in the conversation.
final class NoticeEntry extends ChatEntry {
  /// Creates the entry.
  const NoticeEntry(super.id, this.kind, this.text);

  /// What kind of hint.
  final NoticeKind kind;

  /// German text.
  final String text;
}
