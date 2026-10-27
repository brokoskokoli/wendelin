import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart' show GpuCheckMode;

import '../../../di/provider_setup.dart';
import '../../../di/tee_restrictions.dart';
import '../../../l10n/l10n.dart';
import '../../attestation/attestation_texts.dart';
import '../../design/design.dart';
import '../gpu_check_section.dart';
import '../settings_page.dart';
import 'attestation_stages_card.dart';

/// Whether the GPU choice is offered (WP159).
///
/// Only with GPU evidence (`true`). Without it (`false`) and while it is
/// unknown (`null`) the choice is hidden and „off“ is saved: „Before“ would
/// block every request for lack of evidence, „After“ would only raise false
/// warnings. A profile that already stores a mode other than „off“ keeps the
/// choice visible, so nothing is loosened silently.
bool gpuChoiceVisible({
  required bool attested,
  required bool? gpuEvidence,
  required GpuCheckMode savedMode,
}) => attested && (gpuEvidence == true || savedMode != GpuCheckMode.off);

StatusCard _noEvidenceCard(AppLocalizations l, bool choiceVisible) =>
    StatusCard(
      key: const ValueKey('noGpuEvidence'),
      status: CheckStatus.info,
      title: l.gpuNoEvidenceFinishTitle,
      // The text refers to the choice below only if it is shown.
      detail: choiceVisible
          ? l.gpuNoEvidenceFinishText(l.gpuNoEvidenceHint)
          : l.gpuNoEvidenceFinishHidden(l.gpuNoEvidenceHint),
    );

/// Step 4: privacy level, monthly budget and warning threshold.
List<Widget> finishStep({
  required AppLocalizations l,
  required SetupTestResult? result,
  required ProviderCapabilities? detected,
  required PrivacyLevel privacy,
  required void Function(PrivacyLevel level) onPrivacy,
  required TextEditingController budget,
  required String? budgetError,
  required double warn,
  required void Function(double w) onWarn,
  required bool attested,
  required GpuCheckMode gpuMode,
  required void Function(GpuCheckMode mode) onGpuMode,
  required bool? gpuEvidence,
  required GpuCheckMode savedGpuMode,
  required VoidCallback onSave,
}) {
  final showGpu = gpuChoiceVisible(
    attested: attested,
    gpuEvidence: gpuEvidence,
    savedMode: savedGpuMode,
  );
  return [
    StatusCard(
      status: CheckStatus.ok,
      title: l.attFinishModelChecked,
      detail: result?.message,
    ),
    if (result != null && result.stages.isNotEmpty)
      AttestationStagesCard(result.stages),
    if (result != null && attested)
      ..._restrictionNote(l, stageViews(result.stages)),
    if (attested && gpuEvidence == false) _noEvidenceCard(l, showGpu),
    if (showGpu) GpuCheckSection(mode: gpuMode, onChanged: onGpuMode),
    if (detected != null)
      Text(
        [
          detected.tools ? l.attFinishToolsYes : l.attFinishToolsNo,
          detected.vision ? l.attFinishImagesYes : l.attFinishImagesNo,
          if (detected.tee) l.attFinishTeeYes,
        ].join(' · '),
        style: WText.mono,
      ),
    SettingsSection(
      title: l.attFinishPrivacyLevel,
      children: [
        // „TEE“ only for profiles whose attestation the app really checks.
        for (final level in PrivacyLevel.values)
          if (level != PrivacyLevel.tee || attested)
            SettingsRow(
              title: level.labelOf(l),
              trailing: privacy == level
                  ? CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected)
                  : PrivacyChip(level),
              onTap: () => onPrivacy(level),
            ),
      ],
    ),
    TextField(
      controller: budget,
      style: WText.body,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: l.attFinishBudgetLabel,
        errorText: budgetError,
      ),
    ),
    SettingsSection(
      title: l.attFinishWarnFrom,
      children: [
        for (final w in const [0.5, 0.8, 0.9])
          SettingsRow(
            title: l.attFinishPercentOfBudget((w * 100).round()),
            onTap: () => onWarn(w),
            trailing: warn == w
                ? CheckStatusIcon(CheckStatus.ok, semanticLabel: l.selected)
                : null,
          ),
      ],
    ),
    PrimaryButton(l.save, onPressed: onSave),
  ];
}

/// Setup note (WP78): what this provider does not deliver. Saving the
/// profile accepts it; the chat then shows a plain green check.
List<Widget> _restrictionNote(AppLocalizations l, List<StageView> stages) {
  final ids = restrictionStages(stages);
  final restricted = [
    for (final s in stages)
      if (ids.contains(s.stage)) s,
  ];
  return _restrictionCard(l, restricted);
}

List<Widget> _restrictionCard(
  AppLocalizations l,
  List<StageView> restricted,
) => [
  if (restricted.isNotEmpty)
    StatusCard(
      key: const ValueKey('restrictionSetupNote'),
      status: CheckStatus.info,
      title: l.attExplainRestrictionsTitle,
      detail: l.attFinishRestrictionNote(
        [
          for (final s in restricted)
            '${stageLabel(l, s.stage)}${s.detail == null ? '' : ' (${s.detail})'}',
        ].join('; '),
      ),
    ),
];
