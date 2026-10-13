import 'package:flutter/material.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

import '../../design/design.dart';
import '../settings_page.dart';

/// Step 1: the provider templates.
List<Widget> templateStep({
  required void Function(ProviderTemplate t) onChoose,
}) => [
  SectionCard(
    children: [
      for (final t in providerTemplates)
        SettingsRow(
          title: t.name,
          trailing: PrivacyChip(t.privacy),
          onTap: () => onChoose(t),
        ),
    ],
  ),
];
