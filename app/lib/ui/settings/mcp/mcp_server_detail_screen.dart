import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
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
import 'mcp_servers_screen.dart' show McpChanges;

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
    final source = ref.read(mcpServerSourceProvider);
    final state = mcpTileState(server, info);
    void update(McpServerConfig next) =>
        unawaited(_guard(context, () => source.update(next)));
    final offered = server.offered;
    final skipped = {for (final s in server.skipped) s.name: s.reason};
    return SettingsPage(
      title: config.name,
      intro: 'Tool-Argumente gehen an diesen Server: ${config.url}',
      children: [
        SectionCard(
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
                        switchIntegration(
                          context,
                          ref,
                          server.integrationId,
                          on,
                        ),
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
        ),
        SettingsSection(
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
                onTap: () => unawaited(_toolSheet(context, ref, tool)),
                trailing: WSwitch(
                  value: config.toolOverrides[tool.name]?.enabled ?? true,
                  semanticLabel: tool.name,
                  onChanged: (on) => update(
                    _withTool(tool.name, (o) => _copy(o, enabled: on)),
                  ),
                ),
              ),
          ],
        ),
        Text(
          'Tippe auf ein Tool für Nachfrage und Risikostufe. MCP-Tools haben '
          'kein Rückgängig: Änderungen passieren auf dem Server.',
          style: WText.caption,
        ),
        SectionCard(
          children: [
            SettingsRow(
              title: 'Alle Tools bestätigen',
              detail: 'Jeder Aufruf fragt nach, egal was der Server angibt',
              trailing: WSwitch(
                value: config.confirmAll,
                semanticLabel: 'Alle Tools bestätigen',
                onChanged: (on) => update(config.copyWith(confirmAll: on)),
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
                onChanged: (on) => update(config.copyWith(sensitive: on)),
              ),
            ),
          ],
        ),
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
              unawaited(_guard(context, () => source.signOut(config.id))),
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

  McpServerConfig _withTool(
    String name,
    McpToolOverride Function(McpToolOverride o) change,
  ) {
    final next = change(config.toolOverrides[name] ?? const McpToolOverride());
    return config.copyWith(
      toolOverrides: {
        for (final e in config.toolOverrides.entries)
          if (e.key != name) e.key: e.value,
        if (next != const McpToolOverride()) name: next,
      },
    );
  }

  static McpToolOverride _copy(
    McpToolOverride o, {
    bool? enabled,
    RiskLevel? Function()? risk,
    bool? autoRun,
  }) => McpToolOverride(
    enabled: enabled ?? o.enabled,
    risk: risk == null ? o.risk : risk(),
    autoRun: autoRun ?? o.autoRun,
  );

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

  /// Level choices of one tool: only stricter than the server's (K8 b);
  /// „ohne Nachfrage“ only for `write` tools (no undo).
  Future<void> _toolSheet(
    BuildContext context,
    WidgetRef ref,
    McpToolInfo tool,
  ) async {
    final source = ref.read(mcpServerSourceProvider);
    final base = mcpBaseRisk(tool.annotations);
    final override = config.toolOverrides[tool.name];
    final mcpTool = server.offered[tool.name];
    final choices =
        <(String, String, McpToolOverride Function(McpToolOverride))>[
          if (base == RiskLevel.read) ...[
            ('Ohne Nachfrage', 'liest nur', (o) => _copy(o, risk: () => null)),
            (
              'Immer nachfragen',
              'jeder Aufruf wird bestätigt',
              (o) => _copy(o, risk: () => RiskLevel.external),
            ),
          ],
          if (base == RiskLevel.write) ...[
            (
              'Immer nachfragen',
              'Standard: kein Rückgängig möglich',
              (o) => _copy(o, autoRun: false),
            ),
            (
              'Ohne Nachfrage',
              'Kein Rückgängig: die Änderung passiert sofort auf dem Server',
              (o) => _copy(o, autoRun: true, risk: () => null),
            ),
          ],
        ];
    bool selected(int i) => switch ((base, i)) {
      (RiskLevel.read, 0) => override?.risk == null,
      (RiskLevel.read, _) => override?.risk != null,
      (RiskLevel.write, 0) =>
        !(override?.autoRun ?? false) || override?.risk != null,
      (RiskLevel.write, _) =>
        (override?.autoRun ?? false) && override?.risk == null,
      _ => false,
    };
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(WSpace.screen),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: WSpace.m,
            children: [
              Text(tool.name, style: WText.mono),
              if (tool.description.isNotEmpty)
                Text(tool.description, style: WText.detail),
              Text(mcpAnnotationText(tool.annotations), style: WText.caption),
              Text(
                'Wirksam: ${mcpToolRiskText(tool, config)}',
                style: WText.label,
              ),
              if (config.confirmAll)
                Text(
                  '„Alle Tools bestätigen“ ist an: jeder Aufruf fragt nach.',
                  style: WText.caption,
                )
              else if (choices.isEmpty)
                Text(
                  'Außenwirkung: fragt immer nach, das lässt sich nicht '
                  'lockern.',
                  style: WText.caption,
                )
              else
                SectionCard(
                  children: [
                    for (final (i, (title, detail, change)) in choices.indexed)
                      SettingsRow(
                        title: title,
                        detail: detail,
                        onTap: () {
                          Navigator.of(sheet).pop();
                          unawaited(
                            _guard(
                              context,
                              () => source.update(_withTool(tool.name, change)),
                            ),
                          );
                        },
                        trailing: selected(i)
                            ? const CheckStatusIcon(
                                CheckStatus.ok,
                                semanticLabel: 'gewählt',
                              )
                            : null,
                      ),
                  ],
                ),
              if (mcpTool != null && mcpTool.unsupportedSchemaParts.isNotEmpty)
                Text(
                  'Nur vom Server geprüft: '
                  '${mcpTool.unsupportedSchemaParts.join(', ')}',
                  style: WText.caption,
                ),
            ],
          ),
        ),
      ),
    );
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

/// OAuth login of [server]; shows a hint if it fails (no browser, denied,
/// aborted).
Future<void> signInMcp(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
) async {
  final source = ref.read(mcpServerSourceProvider);
  try {
    final check = await source.signIn(server.config.id);
    if (context.mounted) {
      showHint(
        context,
        check.ok ? 'Angemeldet' : 'Prüfung: ${mcpCheckText(check)}',
      );
    }
  } on McpSignInException catch (e) {
    if (context.mounted) showHint(context, e.message);
  } on McpException catch (e) {
    if (context.mounted) {
      showHint(context, 'Anmeldung fehlgeschlagen: ${e.message}');
    }
  }
}

/// Asks for the secrets an imported [server] needs (token, header values);
/// an OAuth server gets a hint to log in on its page.
Future<void> askSecrets(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
) async {
  switch (server.config.auth) {
    case McpNoAuth():
      return;
    case McpOAuth():
      showHint(
        context,
        '„${server.config.name}“: auf der Serverseite anmelden',
      );
    case McpBearerAuth(:final secretRef):
      await askSecret(context, ref, server, secretRef, 'Bearer-Token');
    case McpHeadersAuth(:final secretRefsByHeader):
      for (final MapEntry(key: header, value: secretRef)
          in secretRefsByHeader.entries) {
        if (!context.mounted) return;
        await askSecret(context, ref, server, secretRef, 'Wert für $header');
      }
  }
}

/// Asks for one secret of [server] (masked, never shown again) and stores
/// it under [secretRef].
Future<void> askSecret(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
  String secretRef,
  String label,
) async {
  final source = ref.read(mcpServerSourceProvider);
  final value = await askText(
    context,
    title: server.config.name,
    label: label,
    action: 'Speichern',
    obscure: true,
  );
  if (value == null || value.isEmpty) return;
  await source.setSecret(server.config.id, secretRef, value);
  if (context.mounted) showHint(context, 'Gespeichert');
}

/// Dialog with one text field; `null` if cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String action,
  bool obscure = false,
  int maxLines = 1,
}) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WColors.surface,
        title: Text(title, style: WText.label),
        content: TextField(
          key: const ValueKey('mcpDialogField'),
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          autocorrect: false,
          enableSuggestions: false,
          maxLines: obscure ? 1 : maxLines,
          style: WText.body,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(action),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() step) async {
  try {
    await step();
  } on McpException catch (e) {
    if (context.mounted) showHint(context, e.message);
  }
}
