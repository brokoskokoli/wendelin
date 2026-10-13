import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/providers.dart';
import '../design/design.dart';
import '../routes.dart';
import 'labels.dart';

/// Page frame with back button and title (settings pages).
class SettingsPage extends StatelessWidget {
  /// Creates the frame.
  const SettingsPage({super.key, required this.title, required this.children});

  /// Page title.
  final String title;

  /// Content below the title.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        WSpace.screen,
        WSpace.screenTop - WSize.tapTargetInset,
        WSpace.screen,
        WSpace.xl24,
      ),
      children: [
        Row(
          spacing: WSpace.m,
          children: [
            WIconButton(
              icon: WIcons.back,
              tooltip: 'Zurück',
              onPressed: () => Navigator.of(context).maybePop(),
              iconSize: WSize.iconSmall,
            ),
            Expanded(child: Text(title, style: WText.screenTitle)),
          ],
        ),
        const SizedBox(height: WSpace.l18 - WSize.tapTargetInset),
        ...children,
      ],
    ),
  );
}

/// Provisional settings page until WP09: switches for the integrations
/// (permission is requested when switching on) and, in debug builds, the
/// demo mode and the design gallery.
class SettingsPlaceholderScreen extends ConsumerWidget {
  /// Creates the page.
  const SettingsPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(toolRegistryProvider);
    final activator = ref.watch(integrationActivatorProvider);
    final demo = ref.watch(demoModeProvider);
    return SettingsPage(
      title: 'Einstellungen',
      children: [
        Text(
          'Nur aktive Integrationen gehen ans Modell. Weitere Einstellungen '
          'folgen.',
          style: WText.intro,
        ),
        const SizedBox(height: WSpace.l18),
        StreamBuilder<void>(
          stream: registry.changes,
          builder: (context, _) => SectionCard(
            children: [
              for (final info in registry.integrations)
                _tile(info, activator.setEnabled, activator.setUp),
            ],
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: WSpace.l18),
          SectionCard(
            title: 'Entwicklung',
            dividers: false,
            spacing: WSpace.m,
            padding: const EdgeInsets.all(WSpace.l),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Demo-Modus (ohne Provider)',
                      style: WText.label,
                    ),
                  ),
                  WSwitch(
                    value: demo,
                    semanticLabel: 'Demo-Modus',
                    onChanged: (on) => unawaited(
                      ref.read(demoModeProvider.notifier).set(enabled: on),
                    ),
                  ),
                ],
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed(AppRoutes.gallery),
                child: const Text('Design-Galerie'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tile(
    IntegrationInfo info,
    Future<IntegrationStatus> Function(String id, {required bool enabled})
    setEnabled,
    Future<IntegrationStatus> Function(String id) setUp,
  ) {
    final integration = info.integration;
    final detail = switch (info.status) {
      IntegrationStatus.unavailable => info.availability.reason,
      IntegrationStatus.setupRequired => 'Berechtigung fehlt',
      IntegrationStatus.error => info.error,
      IntegrationStatus.active ||
      IntegrationStatus.available => '${integration.tools.length} Tools',
    };
    return IntegrationTile(
      name: integration.displayName,
      icon: integrationIcon(integration.id),
      status: info.status,
      detail: detail,
      sensitive: integration.sensitive,
      onToggle: (on) => unawaited(setEnabled(integration.id, enabled: on)),
      onAction: () => unawaited(setUp(integration.id)),
    );
  }
}

/// Placeholder of the provider setup (comes with WP09).
class ProviderSetupPlaceholderScreen extends StatelessWidget {
  /// Creates the page.
  const ProviderSetupPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) => SettingsPage(
    title: 'Provider einrichten',
    children: [
      Text(
        'Die Einrichtung von Providern (Vorlage wählen, API-Key, '
        'Verbindungstest) kommt mit dem nächsten Ausbauschritt.',
        style: WText.intro,
      ),
    ],
  );
}
