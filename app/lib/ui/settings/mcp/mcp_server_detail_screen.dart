import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/providers.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../integration_detail_screen.dart'
    show IntegrationDetailScreen, SensitiveLevelSection;
import '../integrations_screen.dart' show switchIntegration;
import '../settings_page.dart';
import 'mcp_labels.dart';
import 'mcp_secret_dialogs.dart';
import 'mcp_servers_screen.dart' show McpChanges;
import 'mcp_tool_sheet.dart';

export 'mcp_secret_dialogs.dart' show askSecret, askSecrets, askText, signInMcp;

/// One MCP server (WP27): state and last check, „Neu laden“, login or
/// token, every tool with switch and level (only stricter, K8 b; „ohne
/// Nachfrage“ only for `write` tools, there is no undo), „Alle Tools
/// bestätigen“, „Sensibel“, delete.
class McpServerDetailScreen extends ConsumerWidget {
  /// Creates the page of server [serverId].
  const McpServerDetailScreen(String this.serverId, {super.key})
    : integrationId = null;

  /// Creates the page of the server with [integrationId] (`mcp_<slug>`),
  /// e.g. from the integration list.
  const McpServerDetailScreen.forIntegration(
    String this.integrationId, {
    super.key,
  }) : serverId = null;

  /// Server id (not the integration id).
  final String? serverId;

  /// Integration id, if opened by it.
  final String? integrationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(mcpServerSourceProvider);
    final registry = ref.watch(toolRegistryProvider);
    return McpChanges(
      streams: [source.changes, registry.changes],
      builder: (context) {
        final server = switch ((serverId, integrationId)) {
          (final id?, _) => source.server(id),
          (_, final id?) => source.byIntegrationId(id),
          _ => null,
        };
        if (server == null) {
          // Not (or no longer) a configured server: the generic page.
          return switch (integrationId) {
            final id? => IntegrationDetailScreen(id),
            null => SettingsPage(title: context.l10n.areaMcp, children: []),
          };
        }
        return _Page(server: server, info: _info(registry, server));
      },
    );
  }

  static IntegrationInfo? _info(ToolRegistry registry, McpServerView s) {
    try {
      return registry.info(s.integrationId);
    } on ArgumentError {
      return null;
    }
  }
}

class _Page extends ConsumerWidget {
  const _Page({required this.server, required this.info});

  final McpServerView server;
  final IntegrationInfo? info;

  McpServerConfig get config => server.config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsPage(
      title: config.name,
      intro: context.l10n.mcpDetailIntro('${config.url}'),
      children: [
        _serverCard(context, ref),
        _toolsSection(context, ref),
        Text(context.l10n.mcpDetailIntroHint, style: WText.caption),
        _optionsCard(context, ref),
        if (config.sensitive) const SensitiveLevelSection(),
        SectionCard(
          children: [
            SettingsRow(
              title: context.l10n.mcpDetailDelete,
              detail: context.l10n.mcpDetailDeleteHint,
              onTap: () => unawaited(_delete(context, ref)),
            ),
          ],
        ),
      ],
    );
  }

  void _update(BuildContext context, WidgetRef ref, McpServerConfig next) {
    final source = ref.read(mcpServerSourceProvider);
    unawaited(guardMcp(context, () => source.update(next)));
  }

  Widget _serverCard(BuildContext context, WidgetRef ref) {
    final state = mcpTileState(context.l10n, server, info);
    return SectionCard(
      children: [
        SettingsRow(
          title: context.l10n.mcpDetailActive,
          detail: state.detail,
          trailing: WSwitch(
            value: info?.enabled ?? false,
            semanticLabel: context.l10n.mcpDetailActiveLabel(config.name),
            onChanged: info == null
                ? null
                : (on) => unawaited(
                    switchIntegration(context, ref, server.integrationId, on),
                  ),
          ),
        ),
        SettingsRow(
          title: context.l10n.mcpLabelsReload,
          detail: context.l10n.mcpDetailLastCheck(
            mcpCheckText(context.l10n, server.check),
          ),
          onTap: () => unawaited(_reload(context, ref)),
          trailing: _checkIcon(context),
        ),
        ..._authRows(context, ref),
      ],
    );
  }

  Widget _toolsSection(BuildContext context, WidgetRef ref) {
    final offered = server.offered;
    final skipped = {for (final s in server.skipped) s.name: s.reason};
    return SettingsSection(
      title: context.l10n.mcpDetailTools,
      children: [
        if (server.toolInfos.isEmpty)
          SettingsRow(
            title: context.l10n.mcpDetailNoTools,
            detail: context.l10n.mcpDetailNoToolsHint,
          ),
        for (final tool in server.toolInfos)
          SettingsRow(
            title: tool.name,
            mono: true,
            detail: [
              if (skipped[tool.name] case final reason?
                  when offered[tool.name] == null)
                reason
              else
                mcpToolRiskText(context.l10n, tool, config),
            ].join(),
            onTap: () =>
                unawaited(showMcpToolSheet(context, ref, server, tool)),
            trailing: WSwitch(
              value: config.toolOverrides[tool.name]?.enabled ?? true,
              semanticLabel: tool.name,
              onChanged: (on) => _update(
                context,
                ref,
                mcpWithTool(
                  config,
                  tool.name,
                  (o) => mcpCopyOverride(o, enabled: on),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _optionsCard(BuildContext context, WidgetRef ref) => SectionCard(
    children: [
      SettingsRow(
        title: context.l10n.mcpDetailConfirmAll,
        detail: context.l10n.mcpDetailConfirmAllHint,
        trailing: WSwitch(
          value: config.confirmAll,
          semanticLabel: context.l10n.mcpDetailConfirmAll,
          onChanged: (on) =>
              _update(context, ref, config.copyWith(confirmAll: on)),
        ),
      ),
      SettingsRow(
        title: context.l10n.mcpDetailSensitive,
        detail: context.l10n.mcpDetailSensitiveHint,
        trailing: WSwitch(
          value: config.sensitive,
          semanticLabel: context.l10n.mcpDetailSensitiveLabel(config.name),
          onChanged: (on) =>
              _update(context, ref, config.copyWith(sensitive: on)),
        ),
      ),
    ],
  );

  Widget? _checkIcon(BuildContext context) => switch (server.check?.status) {
    null => null,
    McpReachability.reachable => const CheckStatusIcon(
      CheckStatus.ok,
      semanticLabel: 'erreichbar',
    ),
    McpReachability.authRequired => CheckStatusIcon(
      CheckStatus.pending,
      semanticLabel: context.l10n.mcpDetailAuthLabel,
    ),
    _ => CheckStatusIcon(
      CheckStatus.failed,
      semanticLabel: context.l10n.mcpDetailUnreachableLabel,
    ),
  };

  List<Widget> _authRows(BuildContext context, WidgetRef ref) {
    final source = ref.read(mcpServerSourceProvider);
    return switch (config.auth) {
      McpNoAuth() => const [],
      McpOAuth() => [
        SettingsRow(
          title: info?.setup.missingSteps.isEmpty ?? false
              ? context.l10n.mcpDetailSignInAgain
              : context.l10n.mcpDetailSignIn,
          detail: context.l10n.mcpDetailOauthHint,
          onTap: () => unawaited(signInMcp(context, ref, server)),
        ),
        SettingsRow(
          title: context.l10n.mcpDetailSignOut,
          detail: context.l10n.mcpDetailSignOutHint,
          onTap: () =>
              unawaited(guardMcp(context, () => source.signOut(config.id))),
        ),
      ],
      McpBearerAuth(:final secretRef) => [
        SettingsRow(
          title: context.l10n.mcpDetailReplaceToken,
          detail: context.l10n.mcpDetailNeverShown,
          onTap: () => unawaited(
            askSecret(
              context,
              ref,
              server,
              secretRef,
              context.l10n.mcpDetailBearer,
            ),
          ),
        ),
      ],
      McpHeadersAuth(:final secretRefsByHeader) => [
        for (final MapEntry(key: header, value: ref_)
            in secretRefsByHeader.entries)
          SettingsRow(
            title: context.l10n.mcpDetailReplaceHeader(header),
            mono: false,
            detail: context.l10n.mcpDetailValueNeverShown,
            onTap: () => unawaited(
              askSecret(
                context,
                ref,
                server,
                ref_,
                context.l10n.mcpDetailValueFor(header),
              ),
            ),
          ),
      ],
    };
  }

  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    final source = ref.read(mcpServerSourceProvider);
    final check = await source.reload(config.id);
    if (context.mounted) {
      showHint(
        context,
        context.l10n.mcpDetailCheck(mcpCheckText(context.l10n, check)),
      );
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final source = ref.read(mcpServerSourceProvider);
    final ok = await confirm(
      context,
      title: context.l10n.mcpDetailDeleteTitle(config.name),
      message: context.l10n.mcpDetailDeleteBody,
      yes: context.l10n.delete,
    );
    if (!ok) return;
    await source.remove(config.id);
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

/// The action of a server's tile: log in, load again or open its page.
Future<void> mcpAction(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
) async {
  final source = ref.read(mcpServerSourceProvider);
  if (server.config.auth is McpOAuth) {
    await signInMcp(context, ref, server);
    return;
  }
  final check = server.check?.status;
  if (check == McpReachability.unreachable ||
      check == McpReachability.protocolError) {
    final next = await source.reload(server.config.id);
    if (context.mounted) {
      showHint(
        context,
        context.l10n.mcpDetailCheck2(mcpCheckText(context.l10n, next)),
      );
    }
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => McpServerDetailScreen(server.config.id),
    ),
  );
}
