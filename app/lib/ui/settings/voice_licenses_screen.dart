import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/voice_settings_providers.dart';
import '../../l10n/l10n.dart';
import 'settings_page.dart';

/// Settings → Sprache → Lizenzen der Sprachmodelle (WP162): license and
/// attribution of every model in the catalog.
class VoiceLicensesScreen extends ConsumerWidget {
  /// Creates the screen.
  const VoiceLicensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(speechModelCatalogProvider);
    return SettingsPage(
      title: context.l10n.voiceScreenModelLicenses,
      children: [
        SettingsSection(
          title: context.l10n.voiceScreenModelLicenses,
          children: [
            for (final m in catalog.models)
              SettingsRow(
                title: m.displayName,
                detail: [m.license, ?m.attribution].join('\n'),
              ),
          ],
        ),
      ],
    );
  }
}
