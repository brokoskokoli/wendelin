import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'barge_debug_sheet.dart';
import 'settings_page.dart';

/// Hint while no barge-in detector exists (wake word model: WP44/WP58).
String bargeInUnavailableText(AppLocalizations l) =>
    l.voiceConvBargeInUnavailable;

/// Labels of the barge-in modes.
Map<BargeInMode, String> bargeInLabels(AppLocalizations l) => {
  BargeInMode.off: l.off,
  BargeInMode.keywords: l.voiceConvBargeKeywords,
  BargeInMode.speech: l.voiceConvBargeSpeech,
};

/// Settings → Sprache → „Gespräch“: continue listening after the answer
/// (default off, K23 d) and barge-in during the speech output (K23 c).
///
/// Choosing the conversation mode counts as the answer to the one-time
/// question: it is never asked again.
class ConversationSettingsSection extends ConsumerWidget {
  /// Creates the section.
  const ConversationSettingsSection({
    super.key,
    required this.settings,
    required this.change,
    required this.bargeInAvailable,
  });

  /// Current settings.
  final VoiceSettings settings;

  /// Stores a change.
  final void Function(VoiceSettings Function(VoiceSettings)) change;

  /// Whether a barge-in detector exists.
  final bool bargeInAvailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final variant = ref.watch(bargeVariantActiveProvider).value ?? false;
    return SettingsSection(
      title: l.onboardingConversation,
      children: [
        if (variant)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: WSpace.l,
              vertical: WSpace.s,
            ),
            child: Text(l.voiceConvCustomBarge, style: WText.detail),
          ),
        SettingsRow(
          title: l.voiceConvKeepListening,
          detail: l.voiceConvKeepListeningDetail,
          trailing: WSwitch(
            value: settings.conversationMode,
            semanticLabel: l.voiceConvKeepListeningLabel,
            onChanged: (v) => change(
              (s) => s.copyWith(conversationMode: v, conversationAsked: true),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WSpace.l,
            vertical: WSpace.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WSpace.s,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l.voiceConvInterrupt, style: WText.label),
                  ),
                  // WP80: the options are visible (formerly a long press).
                  TextButton(
                    onPressed: () => showBargeDebugSheet(context),
                    child: Text(l.voiceConvAdvanced),
                  ),
                ],
              ),
              Text(
                bargeInAvailable
                    ? l.voiceConvInterruptHint
                    : bargeInUnavailableText(l),
                style: WText.detail,
              ),
              Wrap(
                spacing: WSpace.s,
                runSpacing: WSpace.s,
                children: [
                  for (final mode in BargeInMode.values)
                    ChoiceChip(
                      label: Text(bargeInLabels(l)[mode]!),
                      selected: settings.bargeIn == mode,
                      onSelected: bargeInAvailable
                          ? (_) => change((s) => s.copyWith(bargeIn: mode))
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
