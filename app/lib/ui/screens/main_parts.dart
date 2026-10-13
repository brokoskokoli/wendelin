import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../design/design.dart';

/// Head of the main screen: lockup and settings button.
class MainHeader extends StatelessWidget {
  /// Creates the head.
  const MainHeader({super.key, required this.onSettings});

  /// Opens the settings.
  final VoidCallback onSettings;

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
        WIconButton(
          icon: WIcons.settings,
          tooltip: 'Einstellungen',
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
  });

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
            ProviderChip(name: providerName!, level: privacy!),
          MetaChip(costLabel, semanticLabel: 'Kosten $costLabel'),
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
    this.micHint,
    this.status,
  });

  /// Whether a request runs (text cannot be sent then).
  final bool running;

  /// Sends the text; returns whether it was accepted.
  final bool Function(String text) onSend;

  /// State of the microphone button.
  final MicState mic;

  /// Tap on the microphone (start, or cancel while active).
  final VoidCallback onMic;

  /// Label of the disabled microphone (why it is off).
  final String? micHint;

  /// Voice hint or error shown above the field.
  final String? status;

  /// Label of the microphone while listening (a tap aborts).
  static const listeningLabel = 'Zuhören abbrechen';

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
            if (widget.status case final status?)
              Text(
                status,
                style: WText.caption,
                textAlign: TextAlign.center,
                semanticsLabel: status,
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
                      hintText: listening
                          ? 'Ich höre zu …'
                          : 'Schreiben statt sprechen',
                      semanticCounterText: '',
                    ),
                  ),
                ),
                MicButton(
                  state: widget.mic,
                  onPressed: widget.mic == MicState.disabled
                      ? null
                      : widget.onMic,
                  compact: true,
                  semanticLabel: switch (widget.mic) {
                    MicState.disabled => widget.micHint,
                    MicState.listening => Composer.listeningLabel,
                    _ => null,
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
        error == null ? 'Noch kein Provider eingerichtet' : 'Provider prüfen',
        style: WText.label,
      ),
      Text(
        error ??
            'Wendelin braucht ein Sprachmodell. Richte einen Provider mit '
                'deinem API-Key ein, danach kannst du loslegen.',
        style: WText.intro,
      ),
      FilledButton(
        onPressed: onSetup,
        child: const Text('Provider einrichten'),
      ),
      if (onDemo != null && kDebugMode)
        OutlinedButton(
          onPressed: onDemo,
          child: const Text('Demo ohne Provider starten'),
        ),
    ],
  );
}
