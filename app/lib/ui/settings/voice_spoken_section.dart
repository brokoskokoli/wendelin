import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../design/design.dart';
import 'settings_page.dart';

/// Label and one-sentence explanation of each level of „Sprechfassung“.
const spokenVersionTexts = {
  SpokenVersion.off: (
    'Aus',
    'Wendelin liest die angezeigte Antwort vor, nur für die Aussprache '
        'aufbereitet.',
  ),
  SpokenVersion.always: (
    'Immer eigene Sprechfassung',
    'Wendelin schreibt zuerst einen kurzen Sprechtext und liest ihn immer '
        'vor, auch nach Inhalten aus dem Web oder von Dritten.',
  ),
  SpokenVersion.protected: (
    'Geschützt',
    'Eigener Sprechtext, aber nach Inhalten aus dem Web oder von Dritten '
        'liest Wendelin die angezeigte Antwort vor.',
  ),
  SpokenVersion.checked: (
    'Mit KI-Prüfung',
    'Nach Inhalten aus dem Web oder von Dritten prüft ein weiterer '
        'Modellaufruf, ob Sprechtext und Antwort übereinstimmen. Die '
        'Sprachausgabe beginnt dann etwas später und kostet etwas mehr.',
  ),
};

/// Warning shown with [SpokenVersion.always].
const spokenVersionAlwaysWarning =
    'Was vorgelesen wird, kann von dem abweichen, was auf dem Bildschirm '
    'steht.';

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
    title: 'Sprechfassung',
    children: [
      for (final entry in spokenVersionTexts.entries)
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
          child: Text(spokenVersionAlwaysWarning, style: WText.detail),
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
    label: 'Sprechfassung $label',
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
