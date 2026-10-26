import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart' show RiskPolicy;

import '../../di/preference_models.dart';
import '../../di/preferences.dart';
import '../../di/providers.dart';
import '../../di/sensitivity.dart';
import '../../l10n/l10n.dart';
import '../design/design.dart';
import '../routes.dart';
import 'security_level_picker.dart';
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
      return SettingsPage(
        title: context.l10n.integrationDetailTitle,
        children: [],
      );
    }
    void update(ToolPrefs next) =>
        unawaited(ref.read(toolPrefsProvider.notifier).set(next));
    return SettingsPage(
      title: integration.displayName,
      intro: integration.sensitive
          ? context.l10n.integrationDetailSensitiveNote
          : null,
      children: [
        if (setupPageFor(id) case final page?) _setupRow(context, page),
        if (id == 'memory') _setupRow(context, AppRoutes.memory),
        _toolsCard(
          context,
          integration,
          prefs,
          hasUndo: hasUndo,
          update: update,
        ),
        InfoBox(context.l10n.integrationDetailTapTool),
        _sensitiveCard(context, integration, prefs, update),
        if (integration.sensitive) const SensitiveLevelSection(),
      ],
    );
  }

  Widget _setupRow(BuildContext context, String page) => SectionCard(
    children: [
      SettingsRow(
        title: switch (id) {
          'web' => context.l10n.integrationDetailSetUpSearch,
          'weather' => context.l10n.weatherSetupTitle,
          'lists' || 'tasks' => context.l10n.integrationDetailManageLists,
          'obsidian' => context.l10n.integrationDetailVaultDaily,
          'bring' => context.l10n.integrationDetailBringAccount,
          'todoist' => context.l10n.integrationDetailTodoistAccount,
          'gtasks' => context.l10n.integrationDetailGoogleTasksAccount,
          'ha' => context.l10n.integrationDetailIntegrationDetailHaSetup,
          'spotify' =>
            context.l10n.integrationDetailIntegrationDetailSpotifyAccount,
          'memory' => context.l10n.integrationDetailViewMemory,
          _ => context.l10n.mcpLabelsSetUp,
        },
        detail: switch (id) {
          'web' => context.l10n.integrationDetailNoSearch,
          'weather' => context.l10n.weatherSetupDetail,
          'memory' => context.l10n.integrationDetailMemoryHint,
          _ => null,
        },
        onTap: () => Navigator.of(context).pushNamed(page),
      ),
    ],
  );

  Widget _toolsCard(
    BuildContext context,
    Integration integration,
    ToolPrefs prefs, {
    required bool hasUndo,
    required void Function(ToolPrefs next) update,
  }) => SectionCard(
    children: [
      for (final tool in integration.tools) ...[
        SettingsRow(
          title: tool.name,
          mono: true,
          detail: riskText(
            context.l10n,
            tool.risk,
            _levelOf(prefs, tool) == SecurityLevel.d,
            hasUndo: hasUndo,
          ),
          trailing: WSwitch(
            value: !prefs.disabled.contains(tool.name),
            semanticLabel: tool.name,
            onChanged: (on) =>
                update(prefs.withEnabled(tool.name, enabled: on)),
          ),
        ),
        // The Home Assistant call tools take the level of the device.
        if (!toolLevelPerDevice(tool.name))
          _picker(context, tool, prefs, update)
        else if (prefs.alwaysConfirm.contains(tool.name))
          _legacyConfirm(context, tool, prefs, update),
      ],
    ],
  );

  /// The level that counts for [tool] (chosen, legacy "always confirm" =
  /// D, else the default of its risk; anything invalid = D).
  static SecurityLevel _levelOf(ToolPrefs prefs, Tool tool) =>
      SecurityLevel.effective(
        prefs.levelOf(tool.name),
        RiskPolicy.defaultLevelFor(tool.risk),
      );

  /// The old "always confirm" of a Home Assistant call tool: it still holds
  /// (D, fail-closed), so it is not dropped silently in the migration (that
  /// would loosen the tool without a decision). The user can remove it here;
  /// the device level then decides alone.
  Widget _legacyConfirm(
    BuildContext context,
    Tool tool,
    ToolPrefs prefs,
    void Function(ToolPrefs next) update,
  ) => Padding(
    padding: const EdgeInsets.only(left: WSpace.xl),
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: ValueKey('levelLegacyRemove_${tool.name}'),
        style: TextButton.styleFrom(
          minimumSize: const Size(WSize.touchMin, WSize.touchMin),
        ),
        onPressed: () => update(prefs.withLevel(tool.name, null)),
        child: Text(context.l10n.levelLegacyRemove, style: WText.caption),
      ),
    ),
  );

  Widget _picker(
    BuildContext context,
    Tool tool,
    ToolPrefs prefs,
    void Function(ToolPrefs next) update,
  ) {
    final base = RiskPolicy.defaultLevelFor(tool.risk);
    final level = _levelOf(prefs, tool);
    return SecurityLevelPicker(
      idKey: tool.name,
      name: tool.name,
      level: level,
      isDefault: prefs.levelOf(tool.name) == null,
      // Loosening a tool with outside effect gets the hint once.
      warnLevels: tool.risk == RiskLevel.external
          ? const {SecurityLevel.a, SecurityLevel.b, SecurityLevel.c}
          : const {},
      warnMessage: context.l10n.levelWarnToolMessage,
      onChanged: (l) =>
          update(prefs.withLevel(tool.name, l == base ? null : l)),
    );
  }

  Widget _sensitiveCard(
    BuildContext context,
    Integration integration,
    ToolPrefs prefs,
    void Function(ToolPrefs next) update,
  ) => SectionCard(
    children: [
      SettingsRow(
        title: context.l10n.mcpAddSensitive,
        detail: context.l10n.mcpDetailSensitiveHint,
        trailing: WSwitch(
          value: integration.sensitive,
          semanticLabel: context.l10n.integrationDetailSensitiveLabel(
            integration.displayName,
          ),
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
String riskText(
  AppLocalizations l,
  RiskLevel risk,
  bool alwaysConfirm, {
  bool hasUndo = true,
}) => switch (risk) {
  RiskLevel.read =>
    alwaysConfirm
        ? l.integrationDetailReadsAsks
        : l.integrationDetailReadsNoAsk,
  RiskLevel.write =>
    alwaysConfirm
        ? l.integrationDetailWritesAsks
        : hasUndo
        ? l.integrationDetailWritesUndo
        : l.integrationDetailWritesNoUndo,
  RiskLevel.external =>
    alwaysConfirm
        ? l.integrationDetailExternalAsks
        : l.integrationDetailExternalNoAsk,
};

/// Minimum privacy level for tools of sensitive integrations.
class SensitiveLevelSection extends ConsumerWidget {
  /// Creates the section.
  const SensitiveLevelSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(toolPrefsProvider);
    final options = <(PrivacyLevel?, String)>[
      (null, context.l10n.integrationDetailLevelAll),
      (PrivacyLevel.eu, context.l10n.integrationDetailLevelEu),
      (PrivacyLevel.tee, context.l10n.integrationDetailLevelTee),
      (PrivacyLevel.local, context.l10n.integrationDetailLevelLocal),
    ];
    return SettingsSection(
      title: context.l10n.integrationDetailSensitiveTitle,
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
                ? CheckStatusIcon(
                    CheckStatus.ok,
                    semanticLabel: context.l10n.selected,
                  )
                : null,
          ),
      ],
    );
  }
}
