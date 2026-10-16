import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../../di/provider_setup.dart';
import '../../../di/tee_restrictions.dart';
import '../../attestation/attestation_texts.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'attestation_stages_card.dart';

/// Step 4: privacy level, monthly budget and warning threshold.
List<Widget> finishStep({
  required SetupTestResult? result,
  required ProviderCapabilities? detected,
  required PrivacyLevel privacy,
  required void Function(PrivacyLevel level) onPrivacy,
  required TextEditingController budget,
  required String? budgetError,
  required double warn,
  required void Function(double w) onWarn,
  required bool attested,
  required VoidCallback onSave,
}) {
  return [
    StatusCard(
      status: CheckStatus.ok,
      title: 'Modell geprüft',
      detail: result?.message,
    ),
    if (result != null && result.stages.isNotEmpty)
      AttestationStagesCard(result.stages),
    if (result != null && attested)
      ..._restrictionNote(stageViews(result.stages)),
    if (detected != null)
      Text(
        [
          detected.tools ? '✓ Tools' : '✕ Tools',
          detected.vision ? '✓ Bilder' : '✕ Bilder',
          if (detected.tee) '✓ TEE',
        ].join(' · '),
        style: WText.mono,
      ),
    SettingsSection(
      title: 'Datenschutzstufe',
      children: [
        // „TEE“ only for profiles whose attestation the app really checks.
        for (final level in PrivacyLevel.values)
          if (level != PrivacyLevel.tee || attested)
            SettingsRow(
              title: level.label,
              trailing: privacy == level
                  ? const CheckStatusIcon(
                      CheckStatus.ok,
                      semanticLabel: 'gewählt',
                    )
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
        labelText: r'Budget pro Monat in $ (optional)',
        errorText: budgetError,
      ),
    ),
    SettingsSection(
      title: 'Warnen ab',
      children: [
        for (final w in const [0.5, 0.8, 0.9])
          SettingsRow(
            title: '${(w * 100).round()} % des Budgets',
            onTap: () => onWarn(w),
            trailing: warn == w
                ? const CheckStatusIcon(
                    CheckStatus.ok,
                    semanticLabel: 'gewählt',
                  )
                : null,
          ),
      ],
    ),
    PrimaryButton('Speichern', onPressed: onSave),
  ];
}

/// Setup note (WP78): what this provider does not deliver. Saving the
/// profile accepts it; the chat then shows a plain green check.
List<Widget> _restrictionNote(List<StageView> stages) {
  final ids = restrictionStages(stages);
  final restricted = [
    for (final s in stages)
      if (ids.contains(s.stage)) s,
  ];
  return _restrictionCard(restricted);
}

List<Widget> _restrictionCard(List<StageView> restricted) => [
  if (restricted.isNotEmpty)
    StatusCard(
      key: const ValueKey('restrictionSetupNote'),
      status: CheckStatus.info,
      title: 'Einschränkungen dieses Anbieters',
      detail:
          '${[for (final s in restricted) '${stageLabel(s.stage)}${s.detail == null ? '' : ' (${s.detail})'}'].join('; ')}. '
          'Das liefert der Anbieter nicht oder Wendelin prüft es nicht, es '
          'wird nur protokolliert. Mit „Speichern“ akzeptierst du das. Sobald '
          'etwas Neues dazukommt, weist Wendelin erneut darauf hin. Mehr '
          'unter „Details“.',
    ),
];
