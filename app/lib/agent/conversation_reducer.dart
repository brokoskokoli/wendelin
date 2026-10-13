import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'bring_share.dart';
import 'chat_entry.dart';
import 'conversation_state.dart';
import 'money.dart';

/// Pure state transitions of the conversation (no I/O, no widgets): what a
/// user message, an [AgentEvent] or an undo update does to the
/// [ConversationState]. Side effects (undo registration, persistence,
/// audit) live in the `AgentController`.
///
/// Text handling follows ADR 0002 §8: [AgentTextDelta]s of one model call
/// form one text entry; tool events close it; [AgentTextReset] removes only
/// the entry of the current call. Thinking is kept in its own entry and
/// shown only on request. Provider blocks never reach this reducer as text
/// (the agent does not stream them).
final class ConversationReducer {
  /// Creates the reducer; [nameOf] gives the display name of a profile.
  const ConversationReducer({
    required this.nameOf,
    this.undoWindow = const Duration(seconds: 10),
  });

  /// Display name of a provider profile.
  final String Function(String profileId) nameOf;

  /// Initial time of an undo offer (the undo manager's window).
  final Duration undoWindow;

  /// The user sent [text]; adds a session marker first if [sessionStart] is
  /// given (new session).
  ConversationState userMessage(
    ConversationState s,
    String text, {
    DateTime? sessionStart,
  }) {
    var next = s;
    if (sessionStart != null) {
      next = _add(next, (id) => SessionStartEntry(id, sessionStart));
    }
    next = _add(next, (id) => UserEntry(id, text));
    return next.copyWith(
      running: true,
      lastRequest: text,
      clearOpen: true,
      clearPending: true,
    );
  }

  /// Adds an informational hint (e.g. „Provider einrichten“).
  ConversationState notice(ConversationState s, NoticeKind kind, String text) =>
      _add(s, (id) => NoticeEntry(id, kind, text));

  /// The open question was answered (the sheet closes).
  ConversationState answered(ConversationState s) =>
      s.copyWith(clearPending: true);

  /// Applies one event of the agent run.
  ConversationState apply(ConversationState s, AgentEvent event) {
    switch (event) {
      case Routed(:final profileId, :final reason):
        final byRule = reason != RuleSet.defaultReason;
        return s.copyWith(
          activeProfileId: profileId,
          clearVerification: true,
          activeRule: byRule ? reason : null,
          clearRule: !byRule,
        );
      case AgentTextDelta(:final text):
        return _appendText(s, text);
      case AgentSpokenText():
        return s; // speech output only, never shown (WP41)
      case AgentThinkingDelta(:final text):
        return _appendThinking(s, text);
      case AgentTextReset():
        return _resetSegment(s);
      case BudgetWarning(
        :final profileId,
        :final spentMicros,
        :final budgetMicros,
      ):
        return notice(
          s,
          NoticeKind.warning,
          'Budget von ${nameOf(profileId)}: ${formatUsd(spentMicros)} von '
          '${formatUsd(budgetMicros)} verbraucht.',
        );
      case ToolCallStarted(:final call):
        final closed = s.copyWith(clearOpen: true);
        if (closed.tool(call.id) != null) return closed;
        return closed.copyWith(
          entries: [
            ...closed.entries,
            ToolEntry(call.id, toolName: call.name),
          ],
        );
      case ConfirmationRequired(:final call):
        return _updateTool(
          s,
          call.id,
          (t) => t.copyWith(phase: ToolPhase.awaitingConfirmation),
        ).copyWith(pending: ToolQuestion(event, request: s.lastRequest ?? ''));
      case EscalationConfirmationRequired(:final fromProfile, :final toProfile):
        return s.copyWith(
          pending: EscalationQuestion(
            event,
            fromName: nameOf(fromProfile),
            toName: nameOf(toProfile),
          ),
        );
      case ToolCallFinished(:final call, :final outcome):
        final phase = phaseOf(outcome);
        final undo = phase == ToolPhase.done ? outcome.undo : null;
        var next = _updateTool(
          s.copyWith(clearOpen: true),
          call.id,
          (t) => t.copyWith(
            phase: phase,
            summary: outcome.summary,
            undoLabel: undo?.label,
            undo: undo == null ? UndoPhase.none : UndoPhase.pending,
            undoRemaining: undo == null ? Duration.zero : undoWindow,
            shareText: bringShareTextFor(call, outcome),
          ),
        );
        final pending = next.pending;
        if (pending is ToolQuestion && pending.event.call.id == call.id) {
          next = next.copyWith(clearPending: true);
        }
        return next;
      case Escalated(:final toProfile):
        // Does not end the segment: the reset after an escalation discards
        // the text of the replaced answer (ADR 0003 §4).
        return _add(
          s.copyWith(
            activeProfileId: toProfile,
            clearVerification: true,
            clearRule: true,
          ),
          (id) => EscalationEntry(id, 'an ${nameOf(toProfile)} übergeben'),
        );
      case Verification(:final profileId, :final status):
        // Receipt check of the answering provider (head of the overlay).
        return profileId == s.activeProfileId || s.activeProfileId == null
            ? s.copyWith(verification: status)
            : s;
      case UsageReported():
        return s;
      case AgentDone(:final finalText):
        var next = s;
        if (finalText.isNotEmpty && !_hasAnswerSinceRequest(s)) {
          next = _add(next, (id) => AssistantTextEntry(id, finalText));
        }
        return next.copyWith(
          running: false,
          clearOpen: true,
          clearPending: true,
        );
      case AgentFailed(:final error, :final message):
        final done = s.copyWith(
          running: false,
          clearOpen: true,
          clearPending: true,
        );
        return error == AgentErrorKind.cancelled
            ? notice(done, NoticeKind.info, 'Abgebrochen.')
            : notice(done, NoticeKind.error, message);
    }
  }

  /// Applies a countdown/undo/expiry update of the undo manager.
  ConversationState undo(ConversationState s, UndoUpdate u) =>
      _updateTool(s, u.callId, (t) {
        final phase = switch (u.state) {
          UndoState.pending => UndoPhase.pending,
          UndoState.undone => UndoPhase.undone,
          UndoState.expired => UndoPhase.expired,
          UndoState.failed => UndoPhase.failed,
        };
        // A late tick must not revive an offer that is already running or
        // over.
        if (phase == UndoPhase.pending && t.undo != UndoPhase.pending) {
          return t;
        }
        return t.copyWith(undo: phase, undoRemaining: u.remaining);
      });

  /// Marks the undo of [callId] as running (button pressed).
  ConversationState undoStarted(ConversationState s, String callId) =>
      _updateTool(
        s,
        callId,
        (t) =>
            t.copyWith(undo: UndoPhase.running, undoRemaining: Duration.zero),
      );

  /// Phase of a finished call from its [outcome]. Outcomes created by the
  /// tool runtime for declined and cancelled calls carry fixed texts.
  static ToolPhase phaseOf(ToolOutcome outcome) {
    if (outcome.isError) {
      return outcome.text == ToolOutcome.cancelledText
          ? ToolPhase.cancelled
          : ToolPhase.failed;
    }
    return outcome.text == ToolOutcome.declinedText
        ? ToolPhase.declined
        : ToolPhase.done;
  }

  ConversationState _appendText(ConversationState s, String text) {
    final id = s.openTextId;
    // Only continue the open entry if nothing was shown after it (e.g. an
    // escalation divider); otherwise the text starts a new entry.
    if (id != null && s.entries.lastOrNull?.id == id) {
      return s.copyWith(
        entries: [
          for (final e in s.entries)
            e is AssistantTextEntry && e.id == id ? e.append(text) : e,
        ],
      );
    }
    final added = _add(s, (id) => AssistantTextEntry(id, text));
    return added.copyWith(openTextId: added.entries.last.id);
  }

  ConversationState _appendThinking(ConversationState s, String text) {
    final id = s.openThinkingId;
    if (id != null && s.entries.lastOrNull?.id == id) {
      return s.copyWith(
        entries: [
          for (final e in s.entries)
            e is ThinkingEntry && e.id == id ? e.append(text) : e,
        ],
      );
    }
    final added = _add(s, (id) => ThinkingEntry(id, text));
    return added.copyWith(openThinkingId: added.entries.last.id);
  }

  ConversationState _resetSegment(ConversationState s) {
    final drop = {?s.openTextId, ?s.openThinkingId};
    return s.copyWith(
      entries: [
        for (final e in s.entries)
          if (!drop.contains(e.id)) e,
      ],
      clearOpen: true,
    );
  }

  bool _hasAnswerSinceRequest(ConversationState s) {
    for (final e in s.entries.reversed) {
      if (e is UserEntry) return false;
      if (e is AssistantTextEntry && e.text.isNotEmpty) return true;
    }
    return false;
  }

  ConversationState _updateTool(
    ConversationState s,
    String callId,
    ToolEntry Function(ToolEntry) update,
  ) => s.copyWith(
    entries: [
      for (final e in s.entries)
        e is ToolEntry && e.id == callId ? update(e) : e,
    ],
  );

  ConversationState _add(
    ConversationState s,
    ChatEntry Function(String id) create,
  ) => s.copyWith(
    entries: [...s.entries, create('e${s.nextSeq}')],
    nextSeq: s.nextSeq + 1,
  );
}
