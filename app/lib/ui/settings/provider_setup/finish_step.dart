import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../../di/provider_setup.dart';
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
  required bool attestationFallback,
  required void Function(bool on) onAttestationFallback,
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
        for (final level in PrivacyLevel.values)
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
    if (attested)
      SectionCard(
        children: [
          SettingsRow(
            title: 'Bei fehlgeschlagener Prüfung ausweichen',
            detail:
                'Besteht die TEE-Prüfung nicht, darf Wendelin die Anfrage an '
                'den nächsten Anbieter der Kette übergeben. Bei privaten '
                'Anfragen nur nach deiner Bestätigung. Standard: aus.',
            trailing: WSwitch(
              value: attestationFallback,
              semanticLabel: 'Bei fehlgeschlagener Prüfung ausweichen',
              onChanged: onAttestationFallback,
            ),
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
