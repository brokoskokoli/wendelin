import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/chat_entry.dart';
import '../../agent/conversation_state.dart';
import '../design/design.dart';
import '../screens/bring_share_card.dart';
import '../screens/confirmation_sheet.dart';
import '../screens/conversation_view.dart';
import '../screens/private_banner.dart';

/// What the assistant overlay shows of the current request: the latest
/// user request and everything after it.
@immutable
final class OverlayExchange {
  /// Creates the exchange.
  const OverlayExchange({
    this.request,
    this.tools = const [],
    this.answer,
    this.notice,
  });

  /// The current exchange of [entries]: the last user entry, the tool
  /// calls and the answer text after it, and the last hint (failure,
  /// cancellation). Reasoning text is never shown in the overlay.
  factory OverlayExchange.of(List<ChatEntry> entries) {
    final start = entries.lastIndexWhere((e) => e is UserEntry);
    final tail = start < 0 ? entries : entries.sublist(start + 1);
    final answer = [
      for (final e in tail)
        if (e is AssistantTextEntry && e.text.trim().isNotEmpty) e.text.trim(),
    ].join('\n\n');
    return OverlayExchange(
      request: start < 0 ? null : (entries[start] as UserEntry).text,
      tools: [for (final e in tail) ?(e is ToolEntry ? e : null)],
      answer: answer.isEmpty ? null : answer,
      notice: [for (final e in tail) ?(e is NoticeEntry ? e.text : null)]
          .lastOrNull,
    );
  }

  /// What the user said or typed.
  final String? request;

  /// Tool calls of the request.
  final List<ToolEntry> tools;

  /// Answer text so far.
  final String? answer;

  /// Last hint (cancelled, failed).
  final String? notice;
}

/// Content of the assistant overlay (docs/design/screens/overlay): head
/// with brand and provider chip, live transcript, tool result cards with
/// undo, the answer, an inline confirmation card, the control bar
/// (keyboard · waveform + microphone · close) and the conversation-mode
/// hint (greyed out until M4).
///
/// Pure display; the screen ([AssistantOverlayScreen]) wires it.
class OverlaySheet extends StatelessWidget {
  /// Creates the sheet content.
  const OverlaySheet({
    super.key,
    required this.providerName,
    required this.privacy,
    required this.exchange,
    required this.mic,
    required this.levels,
    required this.onMic,
    required this.onClose,
    required this.onKeyboard,
    required this.onUndo,
    this.checkStatus,
    this.listening = false,
    this.question,
    this.onAnswer,
    this.hint = ConfirmationHint.tap,
    this.status,
    this.locked = false,
    this.onUnlock,
    this.typing,
    this.conversationMode = false,
    this.privateSince,
    this.onNewConversation,
  });

  /// Since when the conversation is private („Unterhaltung privat“).
  final DateTime? privateSince;

  /// Starts a new conversation (ends the private one).
  final VoidCallback? onNewConversation;

  /// Active provider (`''` = none set up).
  final String providerName;

  /// Its privacy level.
  final PrivacyLevel privacy;

  /// Receipt status (TEE), if any.
  final CheckStatus? checkStatus;

  /// Current request and answer.
  final OverlayExchange exchange;

  /// Whether the microphone is open (placeholder instead of transcript).
  final bool listening;

  /// Microphone button state.
  final MicState mic;

  /// Recent microphone levels (0–1).
  final List<double> levels;

  /// Microphone tap.
  final VoidCallback onMic;

  /// Close button (cancels and closes the overlay).
  final VoidCallback onClose;

  /// Keyboard button (text input instead of speech).
  final VoidCallback onKeyboard;

  /// Undo of a tool call.
  final ValueChanged<String> onUndo;

  /// Open confirmation (shown in the same sheet).
  final PendingQuestion? question;

  /// Answers [question].
  final void Function(bool yes)? onAnswer;

  /// Hint under the confirmation card.
  final ConfirmationHint hint;

  /// Voice hint or error.
  final String? status;

  /// Device locked (or lock state not known yet): nothing personal is
  /// shown, only the unlock prompt.
  final bool locked;

  /// Asks for unlocking.
  final VoidCallback? onUnlock;

  /// Text field shown instead of the transcript (keyboard mode).
  final Widget? typing;

  /// Whether the conversation mode is available (M4); until then its hint
  /// is greyed out.
  final bool conversationMode;

  /// Hint of the conversation mode (design text).
  static const followUpHint = 'Hört noch 5 s zu · „Stopp“ beendet';

  /// Hint while the conversation mode does not exist yet.
  static const followUpComingHint =
      'Gesprächsmodus kommt mit M4 · „Stopp“ beendet';

  /// Shown on the lock screen instead of any content.
  static const lockedTitle = 'Gerät entsperren';

  /// Explanation on the lock screen.
  static const lockedText =
      'Auf dem Sperrbildschirm zeigt und sagt Wendelin nichts aus deinen '
      'Daten. Nach dem Entsperren hört Wendelin zu.';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WSpace.l18,
    children: [
      const SheetDragHandle(),
      SheetHeader(
        trailing: providerName.isEmpty
            ? const SizedBox.shrink()
            : ProviderChip(
                name: providerName,
                level: privacy,
                status: checkStatus,
              ),
      ),
      Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WSpace.l18,
            children: locked ? _lockedContent() : _content(),
          ),
        ),
      ),
      _controls(),
      // An open confirmation replaces the conversation-mode hint with how
      // to answer (always visible, below the scrolling content).
      if (_asking)
        hint.widget
      else
        Opacity(
          opacity: conversationMode ? 1 : WOpacity.inactive,
          child: Text(
            conversationMode ? followUpHint : followUpComingHint,
            style: WText.caption,
            textAlign: TextAlign.center,
          ),
        ),
    ],
  );

  bool get _asking {
    final q = question;
    return !locked && q != null && !q.answered && onAnswer != null;
  }

  /// While the lock state is still unknown ([onUnlock] `null`) the sheet
  /// stays empty.
  List<Widget> _lockedContent() => [
    if (onUnlock != null) ...[
      Text(lockedTitle, style: WText.transcript),
      Text(lockedText, style: WText.answer),
      FilledButton(onPressed: onUnlock, child: const Text('Entsperren')),
    ],
  ];

  List<Widget> _content() {
    final request = exchange.request;
    final q = question;
    final statusText = status ?? exchange.notice;
    // Open confirmation: the same sheet as in docs/design/screens/
    // bestaetigung (quote, card, hint), nothing else.
    if (q != null && _asking) {
      return [
        if (request != null) Text('„$request“', style: WText.quote),
        confirmationCardFor(
          q,
          onAnswer!,
          toolRisk: q is ToolQuestion ? q.event.risk : RiskLevel.external,
          privateSince: privateSince,
        ),
        if (statusText != null) Text(statusText, style: WText.caption),
      ];
    }
    return [
      if (privateSince case final since?)
        PrivateConversationBanner(
          since: since,
          onNewConversation: onNewConversation,
        ),
      ?typing,
      if (typing == null)
        if (listening && (request == null || mic == MicState.listening))
          Text(
            'Ich höre zu …',
            style: WText.transcript.copyWith(color: WColors.textMuted),
          )
        else if (request != null)
          Text('„$request“', style: WText.transcript),
      for (final t in exchange.tools)
        if (ToolEntryCard.isCard(t))
          ToolEntryCard(t, onUndo: onUndo)
        else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ToolChip(t.toolName, status: _status(t)),
          ),
      for (final t in exchange.tools)
        if (BringShareCard.applies(t)) BringShareCard(t),
      if (exchange.answer case final answer?)
        AssistantText(answer, large: true),
      if (statusText != null) Text(statusText, style: WText.caption),
    ];
  }

  Widget _controls() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      WIconButton(
        icon: WIcons.keyboard,
        tooltip: 'Texteingabe',
        shape: WIconButtonShape.round,
        onPressed: locked ? null : onKeyboard,
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: WSpace.l,
        children: [
          Waveform(
            amplitudes: _bars(),
            color: mic == MicState.disabled
                ? WColors.line
                : WColors.accentLight,
          ),
          MicButton(
            state: mic,
            onPressed: mic == MicState.disabled ? null : onMic,
            semanticLabel: switch (mic) {
              MicState.idle => 'Weiter sprechen',
              MicState.listening => 'Zuhören abbrechen',
              _ => null,
            },
          ),
        ],
      ),
      WIconButton(
        icon: WIcons.close,
        tooltip: 'Beenden',
        shape: WIconButtonShape.round,
        iconSize: WSize.iconSmall,
        onPressed: onClose,
      ),
    ],
  );

  /// Number of waveform bars.
  static const bars = 6;

  /// [bars] bars, newest level right; flat without levels.
  List<double> _bars() {
    final recent = levels.length > bars
        ? levels.sublist(levels.length - bars)
        : levels;
    return [for (var i = recent.length; i < bars; i++) 0.0, ...recent];
  }

  static CheckStatus _status(ToolEntry e) => switch (e.phase) {
    ToolPhase.running || ToolPhase.awaitingConfirmation => CheckStatus.pending,
    ToolPhase.done => CheckStatus.ok,
    ToolPhase.failed ||
    ToolPhase.declined ||
    ToolPhase.cancelled => CheckStatus.failed,
  };
}
