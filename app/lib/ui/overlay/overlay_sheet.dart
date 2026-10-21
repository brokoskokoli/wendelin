import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../agent/chat_entry.dart';
import '../../agent/conversation_state.dart';
import '../../agent/outgoing_preview.dart';
import '../../l10n/l10n.dart';
import '../attestation/attestation_texts.dart' show gpuBlockReason;
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
    this.hearing = false,
    required this.levels,
    required this.onMic,
    required this.onClose,
    required this.onKeyboard,
    required this.onUndo,
    this.checkStatus,
    this.listening = false,
    this.preparing = false,
    this.question,
    this.onAnswer,
    this.hint = ConfirmationHint.tap,
    this.status,
    this.locked = false,
    this.onUnlock,
    this.lockedNotice,
    this.typing,
    this.conversationMode = false,
    this.followUpUntil,
    this.now = DateTime.now,
    this.privateSince,
    this.privateByRequest = true,
    this.onNewConversation,
    this.gpuBlock,
    this.onGpuBlock,
  });

  /// A request stopped by the GPU check (WP82): shown as a card with the
  /// offer to send it once without the check.
  final GpuBlock? gpuBlock;

  /// Answers [gpuBlock]: `true` sends the request once without GPU check.
  final void Function({required bool sendWithout})? onGpuBlock;

  /// Whether the private state comes from a „privat“ request.
  final bool privateByRequest;

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

  /// The microphone buffers while the speech models load („Moment …“).
  final bool preparing;

  /// Microphone button state.
  final MicState mic;

  /// Wendelin hört während der Ausgabe mit (WP113).
  final bool hearing;

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

  /// Fixed hint on the lock screen (no content), e.g. the request was
  /// discarded because the unlock was cancelled (WP114).
  final String? lockedNotice;

  /// Text field shown instead of the transcript (keyboard mode).
  final Widget? typing;

  /// Whether the conversation mode is available (M4); until then its hint
  /// is greyed out.
  final bool conversationMode;

  /// End of the open follow-up window (listening without a tap), if any.
  final DateTime? followUpUntil;

  /// Current time for the countdown of the window.
  final DateTime Function() now;

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
            children: locked ? _lockedContent(context) : _content(context),
          ),
        ),
      ),
      _controls(context),
      // An open confirmation replaces the conversation-mode hint with how
      // to answer (always visible, below the scrolling content).
      if (_asking)
        hint.widget(context.l10n, outgoing: outgoingPreviewOf(question)?.kind)
      else
        Opacity(
          opacity: conversationMode ? 1 : WOpacity.inactive,
          child: _modeHint(context),
        ),
    ],
  );

  Widget _modeHint(BuildContext context) {
    Text text(String t) =>
        Text(t, style: WText.caption, textAlign: TextAlign.center);
    final until = followUpUntil;
    if (until != null) {
      return FollowUpCountdown(
        until: until,
        now: now,
        builder: (_, seconds) =>
            text(context.l10n.overlayFollowUpWindow(seconds)),
      );
    }
    // The countdown only shows while the window is really open (WP74); with
    // the mode on but no window there is nothing to announce.
    return conversationMode
        ? const SizedBox.shrink()
        : text(context.l10n.overlayFollowUpComing);
  }

  bool get _asking {
    final q = question;
    return !locked && q != null && !q.answered && onAnswer != null;
  }

  /// While the lock state is still unknown ([onUnlock] `null`) the sheet
  /// stays empty.
  List<Widget> _lockedContent(BuildContext context) => [
    if (onUnlock != null) ...[
      Text(context.l10n.overlayLockedTitle, style: WText.transcript),
      Text(context.l10n.overlayLockedText, style: WText.answer),
      if (lockedNotice != null) Text(lockedNotice!, style: WText.answer),
      FilledButton(
        onPressed: onUnlock,
        child: Text(context.l10n.overlayUnlock),
      ),
    ],
  ];

  List<Widget> _content(BuildContext context) {
    final request = exchange.request;
    final q = question;
    final statusText = status ?? exchange.notice;
    final block = gpuBlock;
    if (!locked && block != null && onGpuBlock != null) {
      return [
        if (request != null)
          Text(
            '„$request“',
            style: WText.quote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        _ScrollIntoView(
          child: ConfirmationCard(
            key: const ValueKey('gpuBlockCard'),
            title: block.noEvidence
                ? context.l10n.gpuNoEvidenceTitle
                : context.l10n.mainGpuCheckFailedTitle,
            detail: block.noEvidence
                ? context.l10n.gpuBlockNoEvidenceDetail
                : context.l10n.gpuBlockNotSent(
                    gpuBlockReason(context.l10n, block.reason),
                  ),
            compact: true,
            toolName: context.l10n.gpuToolName,
            risk: RiskLevel.external,
            onYes: () => onGpuBlock!(sendWithout: true),
            onNo: () => onGpuBlock!(sendWithout: false),
            yesLabel: context.l10n.mainSendWithoutGpuCheck,
            noLabel: context.l10n.cancel,
          ),
        ),
      ];
    }
    // Open confirmation: the same sheet as in docs/design/screens/
    // bestaetigung (quote, card, hint), nothing else.
    if (q != null && _asking) {
      return [
        if (request != null) Text('„$request“', style: WText.quote),
        _ScrollIntoView(
          child: confirmationCardFor(
            context.l10n,
            q,
            onAnswer!,
            toolRisk: q is ToolQuestion ? q.event.risk : RiskLevel.external,
            privateSince: privateSince,
            privateByRequest: privateByRequest,
          ),
        ),
        if (statusText != null) Text(statusText, style: WText.caption),
      ];
    }
    return [
      if (privateSince case final since?)
        PrivateConversationBanner(
          since: since,
          byRequest: privateByRequest,
          onNewConversation: onNewConversation,
        ),
      ?typing,
      if (typing == null)
        if (listening &&
            (request == null ||
                mic == MicState.listening ||
                mic == MicState.preparing))
          Text(
            preparing
                ? context.l10n.momentPlease
                : followUpUntil != null
                ? context.l10n.followUpListening
                : context.l10n.mainListening,
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

  Widget _controls(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      WIconButton(
        icon: WIcons.keyboard,
        tooltip: context.l10n.overlayTextInput,
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
            hearing: hearing,
            onPressed: mic == MicState.disabled ? null : onMic,
            semanticLabel: switch (mic) {
              MicState.idle => context.l10n.overlayKeepTalking,
              MicState.listening => context.l10n.mainCancelListening,
              _ => null,
            },
          ),
        ],
      ),
      WIconButton(
        icon: WIcons.close,
        tooltip: context.l10n.overlayEnd,
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

/// Scrolls its child to the end of the visible area once shown, so the
/// buttons of a tall card stay reachable with wide fonts or large text.
class _ScrollIntoView extends StatefulWidget {
  const _ScrollIntoView({required this.child});

  final Widget child;

  @override
  State<_ScrollIntoView> createState() => _ScrollIntoViewState();
}

class _ScrollIntoViewState extends State<_ScrollIntoView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, alignment: 1);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
