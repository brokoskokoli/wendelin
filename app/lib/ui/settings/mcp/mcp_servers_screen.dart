import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/mcp/mcp_source.dart';
import '../../../di/providers.dart';
import '../../design/design.dart';
import '../export.dart';
import '../integrations_screen.dart' show switchIntegration;
import '../settings_page.dart';
import 'mcp_add_server_screen.dart';
import 'mcp_labels.dart';
import 'mcp_server_detail_screen.dart';

/// Settings → MCP-Server (WP27): every configured server with state and
/// switch, „+ Server“ (templates or free entry), export and import of the
/// list without secrets.
class McpServersScreen extends ConsumerWidget {
  /// Creates the screen.
  const McpServersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(mcpServerSourceProvider);
    final registry = ref.watch(toolRegistryProvider);
    final sync = ref.watch(userIntegrationSyncProvider);
    return SettingsPage(
      title: 'MCP-Server',
      intro:
          'Tools von MCP-Servern, z. B. auf dem Homeserver über Tailscale. '
          'Tool-Argumente gehen an den jeweiligen Server.',
      children: [
        McpChanges(
          streams: [source.changes, registry.changes, sync.changes],
          builder: (context) => FutureBuilder<void>(
            future: source.ready(),
            builder: (context, _) => _list(registry, source.servers),
          ),
        ),
        WideButton(
          '+ Server',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const McpAddServerScreen()),
          ),
        ),
        SectionCard(
          children: [
            SettingsRow(
              title: 'Exportieren',
              detail: 'Serverliste ohne Tokens und Passwörter',
              onTap: () => unawaited(_export(ref)),
            ),
            SettingsRow(
              title: 'Importieren',
              detail: 'Zugangsdaten werden neu abgefragt',
              onTap: () => unawaited(_import(context, ref)),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _list(ToolRegistry registry, List<McpServerView> servers) {
    if (servers.isEmpty) {
      return const SectionCard(
        children: [
          SettingsRow(
            title: 'Noch kein Server',
            detail: 'Vorlage wählen oder eigene Adresse eintragen',
          ),
        ],
      );
    }
    return SectionCard(
      children: [
        for (final server in servers)
          McpServerTile(server, info: _info(registry, server)),
      ],
    );
  }

  static IntegrationInfo? _info(ToolRegistry registry, McpServerView server) {
    try {
      return registry.info(server.integrationId);
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _export(WidgetRef ref) async {
    final source = ref.read(mcpServerSourceProvider);
    final registry = ref.read(toolRegistryProvider);
    final export = ref.read(exporterProvider);
    await export(
      'wendelin-mcp-server.json',
      'application/json',
      source.exportJson(enabled: (id) => _enabled(registry, id)),
    );
  }

  static bool _enabled(ToolRegistry registry, String id) {
    try {
      return registry.info(id).enabled;
    } on ArgumentError {
      return false;
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final source = ref.read(mcpServerSourceProvider);
    final json = await askText(
      context,
      title: 'Serverliste importieren',
      label: 'Inhalt der Exportdatei',
      action: 'Importieren',
      maxLines: 6,
    );
    if (json == null || json.trim().isEmpty || !context.mounted) return;
    final List<McpServerView> added;
    try {
      added = await source.importJson(json);
    } on FormatException catch (e) {
      if (context.mounted) showHint(context, e.message);
      return;
    } on McpException catch (e) {
      if (context.mounted) showHint(context, e.message);
      return;
    }
    // Secrets are not in the file: ask for them now.
    for (final server in added) {
      if (!context.mounted) return;
      await askSecrets(context, ref, server);
    }
    if (context.mounted) {
      showHint(
        context,
        added.length == 1
            ? '1 Server importiert (ausgeschaltet)'
            : '${added.length} Server importiert (ausgeschaltet)',
      );
    }
  }
}

/// One server as [IntegrationTile] with switch; tapping opens its page.
class McpServerTile extends ConsumerWidget {
  /// Creates the tile for [server] with its registry [info].
  const McpServerTile(this.server, {super.key, required this.info});

  /// The server.
  final McpServerView server;

  /// Registry state, `null` while not registered.
  final IntegrationInfo? info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = mcpTileState(server, info);
    return InkWell(
      onTap: () => openMcpServer(context, server.config.id),
      child: IntegrationTile(
        name: server.config.name,
        icon: WIcons.globe,
        status: state.status,
        detail: state.detail,
        kind: 'MCP',
        sensitive: server.config.sensitive,
        actionLabel: state.action,
        onToggle: info == null
            ? null
            : (on) => unawaited(
                switchIntegration(context, ref, server.integrationId, on),
              ),
        onAction: () => unawaited(mcpAction(context, ref, server)),
      ),
    );
  }
}

/// Opens the page of server [serverId].
void openMcpServer(BuildContext context, String serverId) => unawaited(
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => McpServerDetailScreen(serverId)),
  ),
);

/// Rebuilds [builder] whenever one of [streams] emits.
class McpChanges extends StatelessWidget {
  /// Creates the builder.
  const McpChanges({super.key, required this.streams, required this.builder});

  /// What to follow.
  final List<Stream<void>> streams;

  /// Content.
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => streams.fold<WidgetBuilder>(
    builder,
    (inner, stream) =>
        (context) => StreamBuilder<void>(
          stream: stream,
          builder: (context, _) => inner(context),
        ),
  )(context);
}
