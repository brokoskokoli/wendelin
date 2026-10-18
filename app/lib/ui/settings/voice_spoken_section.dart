import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Label and one-sentence explanation of each level of „Sprechfassung“.
Map<SpokenVersion, (String, String)> spokenVersionTexts(AppLocalizations l) => {
  SpokenVersion.off: (l.off, l.voiceSpokenOffDetail),
  SpokenVersion.always: (l.voiceSpokenAlwaysTitle, l.voiceSpokenAlwaysDetail),
  SpokenVersion.protected: (
    l.voiceSpokenProtectedTitle,
    l.voiceSpokenProtectedDetail,
  ),
  SpokenVersion.checked: (
    l.voiceSpokenCheckedTitle,
    l.voiceSpokenCheckedDetail,
  ),
};

/// Warning shown with [SpokenVersion.always].
String spokenVersionAlwaysWarning(AppLocalizations l) =>
    l.voiceSpokenAlwaysWarning;

/// Settings → Sprache → „Antworten“: the level of the separate spoken text
/// (K21, WP55).
class SpokenVersionSection extends StatelessWidget {
  /// Creates the section.
  const SpokenVersionSection({
    super.key,
    required this.settings,
    required this.change,
  });

  /// Current settings.
  final VoiceSettings settings;

  /// Applies a change to the settings.
  final void Function(VoiceSettings Function(VoiceSettings)) change;

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: context.l10n.voiceSpokenTitle,
    children: [
      for (final entry in spokenVersionTexts(context.l10n).entries)
        _Option(
          level: entry.key,
          label: entry.value.$1,
          detail: entry.value.$2,
          selected: settings.spokenVersion == entry.key,
          onTap: () => change((s) => s.copyWith(spokenVersion: entry.key)),
        ),
      if (settings.spokenVersion == SpokenVersion.always)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WSpace.l,
            vertical: WSpace.m,
          ),
          child: Text(
            spokenVersionAlwaysWarning(context.l10n),
            style: WText.detail,
          ),
        ),
    ],
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.level,
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final SpokenVersion level;
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: context.l10n.voiceSpokenSemantic(label),
    excludeSemantics: true,
    child: InkWell(
      key: ValueKey('spoken-${level.name}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WSpace.l,
          vertical: WSpace.m,
        ),
        child: Row(
          spacing: WSpace.m,
          children: [
            // Selected: the check mark (shape, not only colour); else a gap.
            selected
                ? const CheckStatusIcon(
                    CheckStatus.ok,
                    size: WSize.statusIconSmall,
                  )
                : const SizedBox.square(dimension: WSize.statusIconSmall),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: WSpace.xs,
                children: [
                  Text(label, style: WText.label),
                  Text(detail, style: WText.detail),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
