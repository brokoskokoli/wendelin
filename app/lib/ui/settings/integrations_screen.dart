import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../di/integration_specs.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../design/design.dart';
import '../screens/labels.dart';
import 'integration_detail_screen.dart';
import 'settings_page.dart';
import 'settings_routes.dart';

/// Settings → Integrationen (docs/design/screens/integrationen): every
/// integration with its state and switch. Switching one on asks for its
/// permission only now, after an explanation.
class IntegrationsScreen extends ConsumerWidget {
  /// Creates the screen.
  const IntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(toolRegistryProvider);
    return SettingsPage(
      title: 'Integrationen',
      intro:
          'Nur aktive Integrationen gehen ans Modell. Ausgeschaltete kosten '
          'keine Tokens.',
      children: [
        StreamBuilder<void>(
          stream: registry.changes,
          builder: (context, _) => SectionCard(
            children: [
              for (final info in displayOrder(registry.integrations))
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => IntegrationDetailScreen(info.id),
                    ),
                  ),
                  child: IntegrationTile(
                    name: info.integration.displayName,
                    icon: integrationIcon(info.id),
                    status: info.status,
                    detail: integrationDetail(info),
                    sensitive: info.integration.sensitive,
                    minPrivacy: info.integration.sensitive
                        ? ref.watch(toolPrefsProvider).sensitiveMinimum
                        : null,
                    onToggle: (on) =>
                        unawaited(switchIntegration(context, ref, info.id, on)),
                    onAction: () =>
                        unawaited(setUpIntegration(context, ref, info.id)),
                  ),
                ),
            ],
          ),
        ),
        Row(
          spacing: WSpace.m,
          children: [
            for (final label in ['+ MCP-Server', '+ HTTP-Tool'])
              Expanded(
                child: WideButton(
                  label,
                  onPressed: () => showHint(context, 'Kommt mit M3.'),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Integrations for display: usable ones first, unavailable ones last
/// (as in the design), otherwise in registry order.
List<IntegrationInfo> displayOrder(List<IntegrationInfo> infos) => [
  for (final i in infos)
    if (i.status != IntegrationStatus.unavailable) i,
  for (final i in infos)
    if (i.status == IntegrationStatus.unavailable) i,
];

/// Second line of an integration tile.
String? integrationDetail(IntegrationInfo info) {
  final tools = info.integration.tools.length;
  return switch (info.status) {
    IntegrationStatus.unavailable => info.availability.reason,
    IntegrationStatus.error => info.error,
    IntegrationStatus.setupRequired => [
      for (final step in info.integration.setup)
        if (info.setup.missingSteps.contains(step.id)) step.label,
    ].join(' · '),
    IntegrationStatus.active => tools == 1 ? '1 Tool' : '$tools Tools',
    // „Verfügbar“ or „Nur an Provider ab …“ (design).
    IntegrationStatus.available => null,
  };
}

IntegrationSpec? _spec(WidgetRef ref, String id) =>
    ref.read(integrationSpecsProvider).where((s) => s.id == id).firstOrNull;

/// Switches [id] on or off. Before a permission request the user sees the
/// integration's explanation and can cancel.
Future<void> switchIntegration(
  BuildContext context,
  WidgetRef ref,
  String id,
  bool on,
) async {
  // Read everything before awaiting: the page may be gone afterwards.
  final activator = ref.read(integrationActivatorProvider);
  final rationale = _spec(ref, id)?.permissionRationale;
  if (on && rationale != null) {
    final ok = await confirm(
      context,
      title: 'Berechtigung',
      message: rationale,
      yes: 'Weiter',
    );
    if (!ok) return;
  }
  await activator.setEnabled(id, enabled: on);
}

/// „Einrichten“: asks for the permission again or opens the page where the
/// missing setup happens (lists, web search).
Future<void> setUpIntegration(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  final registry = ref.read(toolRegistryProvider);
  final activator = ref.read(integrationActivatorProvider);
  final page = setupPageFor(id);
  if (page != null) {
    await Navigator.of(context).pushNamed(page);
    await registry.refresh(id);
    return;
  }
  final rationale = _spec(ref, id)?.permissionRationale;
  if (rationale != null) {
    final ok = await confirm(
      context,
      title: 'Berechtigung',
      message: rationale,
      yes: 'Weiter',
    );
    if (!ok) return;
  }
  await activator.setUp(id);
}
