import 'package:flutter/material.dart';
import 'package:wendelin_providers/wendelin_providers.dart' show GpuCheckMode;

import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// Text of the GPU modes (title, explanation).
(String, String) gpuModeText(AppLocalizations l, GpuCheckMode mode) =>
    switch (mode) {
      GpuCheckMode.off => (l.gpuModeOff, l.gpuModeOffText),
      GpuCheckMode.before => (l.gpuModeBefore, l.gpuModeBeforeText),
      GpuCheckMode.after => (l.gpuModeAfter, l.gpuModeAfterText),
    };

/// „GPU-Prüfung über NVIDIA“ of one TEE profile: off, before or after the
/// request.
class GpuCheckSection extends StatelessWidget {
  /// Creates the section for [mode].
  const GpuCheckSection({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  /// Mode of the profile.
  final GpuCheckMode mode;

  /// The user picked another mode.
  final void Function(GpuCheckMode mode) onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: WSpace.s,
    children: [
      SettingsSection(
        title: context.l10n.gpuSectionTitle,
        children: [
          for (final m in GpuCheckMode.values)
            SettingsRow(
              title: gpuModeText(context.l10n, m).$1,
              detail: gpuModeText(context.l10n, m).$2,
              onTap: () => onChanged(m),
              trailing: m == mode
                  ? CheckStatusIcon(
                      CheckStatus.ok,
                      semanticLabel: context.l10n.selected,
                    )
                  : null,
            ),
        ],
      ),
      InfoBox(context.l10n.gpuSectionNote),
    ],
  );
}
