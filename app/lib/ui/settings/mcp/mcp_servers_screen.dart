import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../di/providers.dart';
import '../../../l10n/l10n.dart';
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
      title: context.l10n.areaMcp,
      intro: context.l10n.mcpServersIntro,
      children: [
        McpChanges(
          streams: [source.changes, registry.changes, sync.changes],
          builder: (context) => FutureBuilder<void>(
            future: source.ready(),
            builder: (context, _) => _list(context, registry, source.servers),
          ),
        ),
        WideButton(
          context.l10n.mcpServersAdd,
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => McpAddServerScreen())),
        ),
        SectionCard(
          children: [
            SettingsRow(
              title: context.l10n.export,
              detail: context.l10n.mcpServersExportHint,
              onTap: () => unawaited(_export(ref)),
            ),
            SettingsRow(
              title: context.l10n.import,
              detail: context.l10n.mcpServersImportHint,
              onTap: () => unawaited(_import(context, ref)),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _list(
    BuildContext context,
    ToolRegistry registry,
    List<McpServerView> servers,
  ) {
    if (servers.isEmpty) {
      return SectionCard(
        children: [
          SettingsRow(
            title: context.l10n.mcpServersNone,
            detail: context.l10n.mcpServersNoneHint,
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
      title: context.l10n.mcpServersImportTitle,
      label: context.l10n.mcpServersContent,
      action: context.l10n.import,
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
            ? context.l10n.mcpServersImportedOne
            : context.l10n.mcpServersImported(added.length),
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
    final state = mcpTileState(context.l10n, server, info);
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
