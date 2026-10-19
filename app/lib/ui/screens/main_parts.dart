import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../l10n/l10n.dart';
import '../../voice/voice_ui_state.dart';
import '../design/design.dart';
import 'quick_switch.dart';

/// Head of the main screen: lockup and settings button.
class MainHeader extends StatelessWidget {
  /// Creates the head.
  const MainHeader({
    super.key,
    required this.onSettings,
    this.onNewConversation,
    this.newConversationEnabled = true,
  });

  /// Opens the settings.
  final VoidCallback onSettings;

  /// „Neues Gespräch“ (same action as the one of the private banner);
  /// `null` hides the button (empty conversation).
  final VoidCallback? onNewConversation;

  /// Whether „Neues Gespräch“ can be tapped (not while a request runs).
  final bool newConversationEnabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WSpace.screen,
      WSpace.screenTop - WSize.tapTargetInset,
      WSpace.screen,
      WSpace.m - WSize.tapTargetInset,
    ),
    child: Row(
      children: [
        const WendelinMark(size: WSize.markHeader),
        const SizedBox(width: WSpace.s10),
        const WendelinWordmark(),
        const Spacer(),
        if (onNewConversation case final onNew?) ...[
          WIconButton(
            icon: WIcons.newChat,
            tooltip: context.l10n.mainNewConversation,
            onPressed: newConversationEnabled ? onNew : null,
          ),
          const SizedBox(width: WSpace.s),
        ],
        WIconButton(
          icon: WIcons.settings,
          tooltip: context.l10n.settingsTitle,
          onPressed: onSettings,
        ),
      ],
    ),
  );
}

/// Chips under the head: active provider with privacy level, cost today.
class MainChips extends StatelessWidget {
  /// Creates the chips; without [providerName] only the cost is shown.
  const MainChips({
    super.key,
    this.providerName,
    this.privacy,
    required this.costLabel,
    this.onQuickSwitch,
  });

  /// Opens the agent quick switch after holding the provider chip (WP94);
  /// `null` = not possible now (request running, fewer than two agents).
  final VoidCallback? onQuickSwitch;

  /// Display name of the active provider.
  final String? providerName;

  /// Its privacy level.
  final PrivacyLevel? privacy;

  /// „heute 0,03 $“.
  final String costLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      WSpace.screen,
      0,
      WSpace.screen,
      WSpace.m,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: WSpace.s,
        runSpacing: WSpace.s,
        children: [
          if (providerName != null && privacy != null)
            QuickSwitchTarget(
              onOpen: onQuickSwitch,
              child: ProviderChip(name: providerName!, level: privacy!),
            ),
          MetaChip(
            costLabel,
            semanticLabel: context.l10n.mainCostLabel(costLabel),
          ),
        ],
      ),
    ),
  );
}

/// Text field and microphone at the bottom of the main screen.
///
/// The microphone starts push-to-talk ([mic] `idle`), shows listening and
/// thinking, and a tap while active cancels ([onMic] decides). Without
/// speech recognition it is disabled with [micHint]. A voice [status]
/// („Ich habe nichts verstanden.“, microphone error) shows above.
class Composer extends StatefulWidget {
  /// Creates the composer.
  const Composer({
    super.key,
    required this.running,
    required this.onSend,
    required this.mic,
    required this.onMic,
    this.levels = const [],
    this.micHint,
    this.status,
    this.notice,
    this.followUpUntil,
    this.now = DateTime.now,
  });

  /// Whether a request runs (text cannot be sent then).
  final bool running;

  /// Sends the text; returns whether it was accepted.
  final bool Function(String text) onSend;

  /// State of the microphone button.
  final MicState mic;

  /// Tap on the microphone (start, or cancel while active).
  final VoidCallback onMic;

  /// Recent microphone levels (0–1) for the listening bar.
  final List<double> levels;

  /// Label of the disabled microphone (why it is off).
  final String? micHint;

  /// Voice hint or error shown above the field.
  final String? status;

  /// Card shown above the field instead of [status] (microphone not
  /// allowed).
  final Widget? notice;

  /// End of the follow-up window (conversation mode) while the microphone
  /// listens without a tap; `null` = ordinary listening.
  final DateTime? followUpUntil;

  /// Current time for the follow-up countdown.
  final DateTime Function() now;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String value) {
    if (widget.onSend(value)) _text.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final listening = widget.mic == MicState.listening;
    final preparing = widget.mic == MicState.preparing;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: WColors.surface, width: WSize.divider),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          WSpace.l,
          WSpace.m,
          WSpace.l,
          WSpace.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: WSpace.s,
          children: [
            if (widget.notice case final notice?)
              notice
            else if (widget.status case final status?)
              Text(
                status,
                style: WText.caption,
                textAlign: TextAlign.center,
                semanticsLabel: status,
              ),
            if (listening)
              ListeningBar(
                levels: widget.levels,
                followUpUntil: widget.followUpUntil,
                now: widget.now,
              ),
            Row(
              spacing: WSpace.m,
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    style: WText.body,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _submit,
                    decoration: InputDecoration(
                      hintText: preparing
                          ? context.l10n.momentPlease
                          : context.l10n.mainTypeInstead,
                      semanticCounterText: '',
                    ),
                  ),
                ),
                // Text in the field: „Senden“ replaces the microphone.
                ValueListenableBuilder(
                  valueListenable: _text,
                  builder: (context, value, _) => value.text.trim().isEmpty
                      ? MicButton(
                          state: widget.mic,
                          onPressed: widget.mic == MicState.disabled
                              ? null
                              : widget.onMic,
                          compact: true,
                          semanticLabel: switch (widget.mic) {
                            MicState.disabled => widget.micHint,
                            MicState.listening =>
                              context.l10n.mainCancelListening,
                            _ => null,
                          },
                        )
                      : SendButton(onPressed: () => _submit(_text.text)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Level bar above the text field while the microphone listens: the
/// waveform of the overlay and „Ich höre zu …“.
class ListeningBar extends StatelessWidget {
  /// Creates the bar for the recent [levels] (0–1, newest last). With
  /// [followUpUntil] it shows the follow-up window („Ich höre noch zu …“
  /// and the remaining time, measured with [now]).
  const ListeningBar({
    super.key,
    required this.levels,
    this.followUpUntil,
    this.now = DateTime.now,
  });

  /// Recent microphone levels.
  final List<double> levels;

  /// End of the follow-up window, if one is open.
  final DateTime? followUpUntil;

  /// Current time for the countdown.
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final until = followUpUntil;
    return until == null
        ? _bar(context.l10n.mainListening)
        : FollowUpCountdown(
            until: until,
            now: now,
            builder: (_, seconds) => _bar(
              context.l10n.mainFollowUpCountdown(
                context.l10n.followUpListening,
                seconds,
              ),
            ),
          );
  }

  Widget _bar(String text) => Semantics(
    liveRegion: true,
    label: text,
    child: ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: WSpace.m,
        children: [
          Waveform(amplitudes: waveBarsOf(levels)),
          Text(text, style: WText.caption),
        ],
      ),
    ),
  );
}

/// One-time hint about the new routing rule „Privat“ (after the M3
/// migration): what it does, a link to the routing page, dismiss.
class PrivateRuleNoticeCard extends StatelessWidget {
  /// Creates the card.
  const PrivateRuleNoticeCard({
    super.key,
    required this.text,
    required this.onOpen,
    required this.onDismiss,
  });

  /// The hint.
  final String text;

  /// Opens the routing page.
  final VoidCallback onOpen;

  /// Hides the hint for good.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => SectionCard(
    dividers: false,
    spacing: WSpace.m,
    padding: const EdgeInsets.all(WSpace.l18),
    children: [
      Text(text, style: WText.intro),
      Row(
        spacing: WSpace.s,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onDismiss,
              child: Text(context.l10n.understood),
            ),
          ),
          Expanded(
            child: FilledButton(
              onPressed: onOpen,
              child: Text(context.l10n.mainViewRouting),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Hint card shown while no provider is set up.
class ProviderSetupCard extends StatelessWidget {
  /// Creates the card.
  const ProviderSetupCard({
    super.key,
    required this.onSetup,
    this.onDemo,
    this.error,
  });

  /// Opens the provider setup.
  final VoidCallback onSetup;

  /// Starts the demo mode (debug builds only); `null` hides the button.
  final VoidCallback? onDemo;

  /// Why the configured provider cannot be used, if it is broken.
  final String? error;

  @override
  Widget build(BuildContext context) => SectionCard(
    dividers: false,
    spacing: WSpace.m,
    padding: const EdgeInsets.all(WSpace.l18),
    children: [
      Text(
        error == null
            ? context.l10n.mainNoProviderYet
            : context.l10n.mainCheckProvider,
        style: WText.label,
      ),
      Text(error ?? context.l10n.mainNeedsModel, style: WText.intro),
      FilledButton(
        onPressed: onSetup,
        child: Text(context.l10n.mainSetUpProvider),
      ),
      if (onDemo != null && kDebugMode)
        OutlinedButton(
          onPressed: onDemo,
          child: Text(context.l10n.mainStartDemo),
        ),
    ],
  );
}
