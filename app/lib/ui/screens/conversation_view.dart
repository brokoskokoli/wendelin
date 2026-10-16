import 'package:flutter/material.dart';

import '../../agent/chat_entry.dart';
import '../attestation/attestation_texts.dart';
import '../design/design.dart';
import 'bring_share_card.dart';
import 'labels.dart';

/// The conversation as a list: user bubbles, tool chips and cards, answer
/// text, escalation dividers and hints. Pure display; actions come in as
/// callbacks.
///
/// Consecutive tool chips and the answer text after them form one answer
/// block (max. 92 % wide), as in the main screen design.
class ConversationView extends StatefulWidget {
  /// Creates the list.
  const ConversationView({
    super.key,
    required this.entries,
    required this.now,
    required this.onUndo,
    this.showThinking = false,
    this.header,
    this.onAttestationTap,
    this.onReattest,
  });

  /// Entries in order.
  final List<ChatEntry> entries;

  /// Current time (for „Heute · 08:12“).
  final DateTime now;

  /// Undo of a tool call (by call id).
  final ValueChanged<String> onUndo;

  /// Whether reasoning text is shown.
  final bool showThinking;

  /// Shown above the entries (e.g. the provider setup hint).
  final Widget? header;

  /// Opens the log entry of a TEE answer (tap on its shield).
  final ValueChanged<AnswerAttestation>? onAttestationTap;

  /// „Neu prüfen“ of the warning card of a failed answer.
  final ValueChanged<AnswerAttestation>? onReattest;

  @override
  State<ConversationView> createState() => _ConversationViewState();
}

class _ConversationViewState extends State<ConversationView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(ConversationView old) {
    super.didUpdateWidget(old);
    // Follow new content while the user is at (or near) the end.
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels > WSize.touchMin) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocks = [?widget.header, ..._blocks()];
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: WSpace.screen,
        vertical: WSpace.s,
      ),
      children: [
        for (final b in blocks)
          Padding(
            padding: const EdgeInsets.only(bottom: WSpace.m14),
            child: b,
          ),
      ],
    );
  }

  List<Widget> _blocks() {
    final out = <Widget>[];
    final chips = <ToolEntry>[];
    void flushChips([Widget? answer]) {
      if (chips.isEmpty && answer == null) return;
      out.add(_AnswerBlock(chips: List.of(chips), answer: answer));
      chips.clear();
    }

    for (final e in widget.entries) {
      switch (e) {
        case ToolEntry() when ToolEntryCard.isCard(e):
          flushChips();
          out.add(_answerWidth(ToolEntryCard(e, onUndo: widget.onUndo)));
        case ToolEntry() when BringShareCard.applies(e):
          chips.add(e);
          flushChips();
          out.add(
            _answerWidth(BringShareCard(e, key: ValueKey('share${e.id}'))),
          );
        case ToolEntry():
          chips.add(e);
        case AssistantTextEntry(:final text, :final attestation):
          final answer = AssistantText(text, key: ValueKey(e.id));
          flushChips(
            attestation == null
                ? answer
                : AttestedAnswer(
                    answer: answer,
                    attestation: attestation,
                    onTap: widget.onAttestationTap,
                    onReattest: widget.onReattest,
                  ),
          );
        case ThinkingEntry(:final text):
          if (widget.showThinking) {
            flushChips();
            out.add(_answerWidth(Text(text, style: WText.caption)));
          }
        case SessionStartEntry(:final at):
          flushChips();
          out.add(
            Text(
              sessionLabel(at, widget.now),
              style: WText.mono,
              textAlign: TextAlign.center,
            ),
          );
        case UserEntry(:final text):
          flushChips();
          out.add(UserBubble(text));
        case EscalationEntry(:final label):
          flushChips();
          out.add(EscalationDivider(label));
        case NoticeEntry():
          flushChips();
          out.add(_answerWidth(_Notice(e)));
      }
    }
    flushChips();
    return out;
  }
}

Widget _answerWidth(Widget child) => FractionallySizedBox(
  widthFactor: WSize.answerMaxFraction,
  alignment: AlignmentDirectional.centerStart,
  child: child,
);

/// Tool chips above the answer text (as in the design).
class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.chips, this.answer});

  final List<ToolEntry> chips;
  final Widget? answer;

  @override
  Widget build(BuildContext context) => _answerWidth(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.s,
      children: [
        if (chips.isNotEmpty)
          Wrap(
            spacing: WSpace.xs6,
            runSpacing: WSpace.xs6,
            children: [
              for (final c in chips)
                ToolChip(c.toolName, key: ValueKey(c.id), status: _status(c)),
            ],
          ),
        ?answer,
      ],
    ),
  );

  static CheckStatus _status(ToolEntry e) => switch (e.phase) {
    ToolPhase.running || ToolPhase.awaitingConfirmation => CheckStatus.pending,
    ToolPhase.done => CheckStatus.ok,
    ToolPhase.failed ||
    ToolPhase.declined ||
    ToolPhase.cancelled => CheckStatus.failed,
  };
}

/// Result card of a `write` tool while it can be undone (and after undo).
class ToolEntryCard extends StatelessWidget {
  /// Creates the card for [entry].
  const ToolEntryCard(this.entry, {super.key, required this.onUndo});

  /// The tool call.
  final ToolEntry entry;

  /// Undo by call id.
  final ValueChanged<String> onUndo;

  /// Whether [entry] is shown as card (undo offered, running or done).
  static bool isCard(ToolEntry e) =>
      e.undo == UndoPhase.pending ||
      e.undo == UndoPhase.running ||
      e.undo == UndoPhase.undone;

  @override
  Widget build(BuildContext context) {
    final undone = entry.undo == UndoPhase.undone;
    final (title, detail) = splitSummary(entry.summary, entry.toolName);
    final canUndo = entry.undo == UndoPhase.pending;
    return ToolResultCard(
      key: ValueKey(entry.id),
      title: title,
      detail: detail,
      toolName: entry.toolName,
      icon: integrationIcon(entry.integrationId),
      undoRemaining: canUndo ? entry.undoRemaining : null,
      undone: undone,
      onUndo: canUndo ? () => onUndo(entry.id) : null,
    );
  }
}

/// Small hint (cancelled, budget, failure, provider data).
class _Notice extends StatelessWidget {
  const _Notice(this.entry);

  final NoticeEntry entry;

  @override
  Widget build(BuildContext context) {
    final status = switch (entry.kind) {
      NoticeKind.warning => CheckStatus.pending,
      NoticeKind.error => CheckStatus.failed,
      NoticeKind.info || NoticeKind.providerData => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: WSpace.s,
      children: [
        if (status != null)
          CheckStatusIcon(status, size: WSize.statusIconSmall),
        Expanded(
          child: Text(
            entry.text,
            style: entry.kind == NoticeKind.providerData
                ? WText.mono
                : WText.caption,
          ),
        ),
      ],
    );
  }
}

/// An answer with the shield of its TEE check and, if the check failed, the
/// warning card with the reason and „Neu prüfen“.
class AttestedAnswer extends StatelessWidget {
  /// Creates the block.
  const AttestedAnswer({
    super.key,
    required this.answer,
    required this.attestation,
    this.onTap,
    this.onReattest,
  });

  /// The answer text.
  final Widget answer;

  /// Result of the check.
  final AnswerAttestation attestation;

  /// Opens the log entry.
  final ValueChanged<AnswerAttestation>? onTap;

  /// Checks the provider again.
  final ValueChanged<AnswerAttestation>? onReattest;

  @override
  Widget build(BuildContext context) {
    final message = attestationMessage(
      attestation.status,
      reasonCode: attestation.reasonCode,
      detail: attestation.detail,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        answer,
        AttestationShield(
          status: message.status,
          label: message.label,
          onTap: onTap == null ? null : () => onTap!(attestation),
        ),
        if (attestation.toolsInvolved) const ToolTlsHint(),
        if (message.title case final title?)
          Padding(
            padding: const EdgeInsets.only(top: WSpace.xs),
            child: StatusCard(
              status: message.status,
              title: title,
              detail: message.text,
              actionBelow: true,
              action: message.canRecheck && onReattest != null
                  ? TextButton(
                      onPressed: () => onReattest!(attestation),
                      style: TextButton.styleFrom(
                        foregroundColor: WColors.link,
                        minimumSize: const Size(WSize.touchMin, WSize.touchMin),
                      ),
                      child: const Text('Neu prüfen'),
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}
