import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/mcp/mcp_source.dart';
import '../../../di/providers.dart';
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
            null => const SettingsPage(title: 'MCP-Server', children: []),
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
      intro: 'Tool-Argumente gehen an diesen Server: ${config.url}',
      children: [
        _serverCard(context, ref),
        _toolsSection(context, ref),
        Text(
          'Tippe auf ein Tool für Nachfrage und Risikostufe. MCP-Tools haben '
          'kein Rückgängig: Änderungen passieren auf dem Server.',
          style: WText.caption,
        ),
        _optionsCard(context, ref),
        if (config.sensitive) const SensitiveLevelSection(),
        SectionCard(
          children: [
            SettingsRow(
              title: 'Server löschen',
              detail: 'Entfernt Konfiguration, Tool-Liste und Zugangsdaten',
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
    final state = mcpTileState(server, info);
    return SectionCard(
      children: [
        SettingsRow(
          title: 'Server aktiv',
          detail: state.detail,
          trailing: WSwitch(
            value: info?.enabled ?? false,
            semanticLabel: '${config.name} aktiv',
            onChanged: info == null
                ? null
                : (on) => unawaited(
                    switchIntegration(context, ref, server.integrationId, on),
                  ),
          ),
        ),
        SettingsRow(
          title: 'Neu laden',
          detail: 'Letzte Prüfung: ${mcpCheckText(server.check)}',
          onTap: () => unawaited(_reload(context, ref)),
          trailing: _checkIcon(),
        ),
        ..._authRows(context, ref),
      ],
    );
  }

  Widget _toolsSection(BuildContext context, WidgetRef ref) {
    final offered = server.offered;
    final skipped = {for (final s in server.skipped) s.name: s.reason};
    return SettingsSection(
      title: 'Tools',
      children: [
        if (server.toolInfos.isEmpty)
          const SettingsRow(
            title: 'Noch keine Tools',
            detail: 'Server einschalten oder neu laden',
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
                mcpToolRiskText(tool, config),
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
        title: 'Alle Tools bestätigen',
        detail: 'Jeder Aufruf fragt nach, egal was der Server angibt',
        trailing: WSwitch(
          value: config.confirmAll,
          semanticLabel: 'Alle Tools bestätigen',
          onChanged: (on) =>
              _update(context, ref, config.copyWith(confirmAll: on)),
        ),
      ),
      SettingsRow(
        title: 'Sensibel',
        detail:
            'Persönliche Daten: Tools nur an Provider ab der '
            'eingestellten Stufe',
        trailing: WSwitch(
          value: config.sensitive,
          semanticLabel: '${config.name} sensibel',
          onChanged: (on) =>
              _update(context, ref, config.copyWith(sensitive: on)),
        ),
      ),
    ],
  );

  Widget? _checkIcon() => switch (server.check?.status) {
    null => null,
    McpReachability.reachable => const CheckStatusIcon(
      CheckStatus.ok,
      semanticLabel: 'erreichbar',
    ),
    McpReachability.authRequired => const CheckStatusIcon(
      CheckStatus.pending,
      semanticLabel: 'Anmeldung nötig',
    ),
    _ => const CheckStatusIcon(
      CheckStatus.failed,
      semanticLabel: 'nicht erreichbar',
    ),
  };

  List<Widget> _authRows(BuildContext context, WidgetRef ref) {
    final source = ref.read(mcpServerSourceProvider);
    return switch (config.auth) {
      McpNoAuth() => const [],
      McpOAuth() => [
        SettingsRow(
          title: info?.setup.missingSteps.isEmpty ?? false
              ? 'Neu anmelden'
              : 'Anmelden',
          detail: 'OAuth-Anmeldung im Browser',
          onTap: () => unawaited(signInMcp(context, ref, server)),
        ),
        SettingsRow(
          title: 'Abmelden',
          detail: 'Vergisst die Tokens auf diesem Gerät',
          onTap: () =>
              unawaited(guardMcp(context, () => source.signOut(config.id))),
        ),
      ],
      McpBearerAuth(:final secretRef) => [
        SettingsRow(
          title: 'Token ersetzen',
          detail: 'Wird nie wieder angezeigt',
          onTap: () => unawaited(
            askSecret(context, ref, server, secretRef, 'Bearer-Token'),
          ),
        ),
      ],
      McpHeadersAuth(:final secretRefsByHeader) => [
        for (final MapEntry(key: header, value: ref_)
            in secretRefsByHeader.entries)
          SettingsRow(
            title: 'Header $header ersetzen',
            mono: false,
            detail: 'Wert wird nie wieder angezeigt',
            onTap: () => unawaited(
              askSecret(context, ref, server, ref_, 'Wert für $header'),
            ),
          ),
      ],
    };
  }

  Future<void> _reload(BuildContext context, WidgetRef ref) async {
    final source = ref.read(mcpServerSourceProvider);
    final check = await source.reload(config.id);
    if (context.mounted) showHint(context, 'Prüfung: ${mcpCheckText(check)}');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final source = ref.read(mcpServerSourceProvider);
    final ok = await confirm(
      context,
      title: '„${config.name}“ löschen?',
      message:
          'Konfiguration, Tool-Liste und alle Zugangsdaten dieses Servers '
          'werden entfernt.',
      yes: 'Löschen',
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
    if (context.mounted) showHint(context, 'Prüfung: ${mcpCheckText(next)}');
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => McpServerDetailScreen(server.config.id),
    ),
  );
}
