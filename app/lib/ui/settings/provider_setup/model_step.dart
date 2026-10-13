import 'package:flutter/material.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../../di/provider_setup.dart';
import '../../design/design.dart';
import '../provider_setup_screen.dart' show ConnectionStatus;
import '../settings_page.dart';

/// Step 3: the models of the provider and a probe of the chosen one.
List<Widget> modelStep({
  required SetupTestResult? connection,
  required List<ModelInfo> models,
  required TextEditingController model,
  required Widget? failure,
  required bool busy,
  required VoidCallback onChanged,
  required void Function(String id) onPick,
  required VoidCallback onProbe,
}) => [
  if (connection case final c?) ConnectionStatus(c),
  if (models.isNotEmpty)
    SettingsSection(
      title: 'Modelle',
      children: [
        for (final m in models.take(50))
          SettingsRow(
            title: m.displayName,
            mono: true,
            onTap: () => onPick(m.id),
            trailing: model.text == m.id
                ? const CheckStatusIcon(
                    CheckStatus.ok,
                    semanticLabel: 'gewählt',
                  )
                : null,
          ),
      ],
    ),
  TextField(
    controller: model,
    style: WText.body,
    onChanged: (_) => onChanged(),
    decoration: const InputDecoration(labelText: 'Modell-ID'),
  ),
  ?failure,
  PrimaryButton(
    busy ? 'Prüfe …' : 'Modell prüfen',
    onPressed: busy || model.text.trim().isEmpty ? null : onProbe,
  ),
];
