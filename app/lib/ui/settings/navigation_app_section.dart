import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../../di/preferences.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import 'settings_page.dart';

/// „Navigations-App“ (WP164 B): which app `maps__navigate` opens when the
/// command names none. Shown for Google Maps and Waze.
class NavigationAppSection extends ConsumerWidget {
  /// Creates the section.
  const NavigationAppSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final chosen = ref.watch(navigationAppProvider);
    final options = <(NavigationApp?, String)>[
      (null, t.navigationAppDefault),
      for (final app in NavigationApp.values) (app, app.label),
    ];
    return SettingsSection(
      key: const ValueKey('navigationAppSection'),
      title: t.navigationAppTitle,
      children: [
        for (final (app, label) in options)
          SettingsRow(
            title: label,
            onTap: () =>
                unawaited(ref.read(navigationAppProvider.notifier).set(app)),
            trailing: chosen == app
                ? CheckStatusIcon(CheckStatus.ok, semanticLabel: t.selected)
                : null,
          ),
        InfoBox(t.navigationAppHelp),
      ],
    );
  }
}
