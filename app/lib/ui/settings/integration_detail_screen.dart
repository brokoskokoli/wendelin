import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../di/sensitivity.dart';
import '../design/design.dart';
import '../routes.dart';
import 'settings_page.dart';
import 'settings_routes.dart';

/// Tools of one integration: each on/off, and `read`/`write` tools can be
/// set to „Immer nachfragen“. Levels can only be made stricter (K8 b):
/// `external` tools always ask.
class IntegrationDetailScreen extends ConsumerWidget {
  /// Creates the page for the integration [id].
  const IntegrationDetailScreen(this.id, {super.key});

  /// Integration id.
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Built-in ones by spec, user-defined ones (MCP, HTTP) from the
    // registry.
    final integration =
        ref.watch(integrationsProvider)[id] ??
        ref
            .watch(toolRegistryProvider)
            .integrations
            .where((i) => i.id == id)
            .firstOrNull
            ?.integration;
    final prefs = ref.watch(toolPrefsProvider);
    // User-defined integrations (MCP, HTTP) have no undo (K12 c).
    final hasUndo = ref.watch(userIntegrationSyncProvider).kindOf(id) == null;
    if (integration == null) {
      return const SettingsPage(title: 'Integration', children: []);
    }
    void update(ToolPrefs next) =>
        unawaited(ref.read(toolPrefsProvider.notifier).set(next));
    return SettingsPage(
      title: integration.displayName,
      intro: integration.sensitive
          ? 'Sensibel: Die Tools gehen nur an Provider ab der Stufe, die du '
                'für sensible Integrationen festlegst.'
          : null,
      children: [
        if (setupPageFor(id) case final page?) _setupRow(context, page),
        if (id == 'memory') _setupRow(context, AppRoutes.memory),
        _toolsCard(integration, prefs, hasUndo: hasUndo, update: update),
        Text(
          'Tippe auf ein Tool, um „Immer nachfragen“ ein- oder auszuschalten.',
          style: WText.caption,
        ),
        _sensitiveCard(integration, prefs, update),
        if (integration.sensitive) const SensitiveLevelSection(),
      ],
    );
  }

  Widget _setupRow(BuildContext context, String page) => SectionCard(
    children: [
      SettingsRow(
        title: switch (id) {
          'web' => 'Suchdienst einrichten',
          'lists' => 'Listen verwalten',
          'obsidian' => 'Vault und Tagesnotizen',
          'bring' => 'Bring!-Konto',
          'ha' => 'Adresse, Token und Geräte',
          'memory' => 'Gedächtnis ansehen',
          _ => 'Einrichten',
        },
        detail: switch (id) {
          'web' => 'Ohne Suchdienst liest Wendelin nur Seiten',
          'memory' => 'Einträge ansehen, ändern, exportieren',
          _ => null,
        },
        onTap: () => Navigator.of(context).pushNamed(page),
      ),
    ],
  );

  Widget _toolsCard(
    Integration integration,
    ToolPrefs prefs, {
    required bool hasUndo,
    required void Function(ToolPrefs next) update,
  }) => SectionCard(
    children: [
      for (final tool in integration.tools)
        SettingsRow(
          title: tool.name,
          mono: true,
          detail: riskText(
            tool.risk,
            prefs.alwaysConfirm.contains(tool.name),
            hasUndo: hasUndo,
          ),
          onTap: tool.risk == RiskLevel.external
              ? null
              : () => update(
                  prefs.withConfirm(
                    tool.name,
                    confirm: !prefs.alwaysConfirm.contains(tool.name),
                  ),
                ),
          trailing: WSwitch(
            value: !prefs.disabled.contains(tool.name),
            semanticLabel: tool.name,
            onChanged: (on) =>
                update(prefs.withEnabled(tool.name, enabled: on)),
          ),
        ),
    ],
  );

  Widget _sensitiveCard(
    Integration integration,
    ToolPrefs prefs,
    void Function(ToolPrefs next) update,
  ) => SectionCard(
    children: [
      SettingsRow(
        title: 'Sensibel',
        detail:
            'Persönliche Daten: Tools nur an Provider ab der '
            'eingestellten Stufe',
        trailing: WSwitch(
          value: integration.sensitive,
          semanticLabel: '${integration.displayName} sensibel',
          onChanged: (on) => update(
            prefs.withSensitive(
              id,
              sensitive: on,
              byDefault: unwrapIntegration(integration).sensitive,
            ),
          ),
        ),
      ),
    ],
  );
}

/// German description of a tool's level and whether it asks.
/// [hasUndo] is false for tools without undo (MCP and HTTP tools).
String riskText(RiskLevel risk, bool alwaysConfirm, {bool hasUndo = true}) =>
    switch (risk) {
      RiskLevel.read =>
        alwaysConfirm ? 'liest · fragt immer nach' : 'liest · ohne Nachfrage',
      RiskLevel.write =>
        alwaysConfirm
            ? 'ändert · fragt immer nach'
            : hasUndo
            ? 'ändert · ohne Nachfrage, 10 s rückgängig'
            : 'ändert · ohne Nachfrage, kein Rückgängig',
      RiskLevel.external => 'Außenwirkung · fragt immer nach',
    };

/// Minimum privacy level for tools of sensitive integrations.
class SensitiveLevelSection extends ConsumerWidget {
  /// Creates the section.
  const SensitiveLevelSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(toolPrefsProvider);
    final options = <(PrivacyLevel?, String)>[
      (null, 'An alle Provider'),
      (PrivacyLevel.eu, 'Ab EU'),
      (PrivacyLevel.tee, 'Ab TEE'),
      (PrivacyLevel.local, 'Nur lokal'),
    ];
    return SettingsSection(
      title: 'Sensible Integrationen',
      children: [
        for (final (level, label) in options)
          SettingsRow(
            title: label,
            onTap: () => unawaited(
              ref
                  .read(toolPrefsProvider.notifier)
                  .set(prefs.withSensitiveMinimum(level)),
            ),
            trailing: prefs.sensitiveMinimum == level
                ? const CheckStatusIcon(
                    CheckStatus.ok,
                    semanticLabel: 'gewählt',
                  )
                : null,
          ),
      ],
    );
  }
}
