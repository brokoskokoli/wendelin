import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../../di/mcp/mcp_providers.dart';
import '../../../l10n/l10n.dart';
import '../../design/design.dart';
import '../settings_page.dart';
import 'mcp_labels.dart';
import 'mcp_secret_dialogs.dart' show guardMcp;

/// [config] with the override of tool [name] changed by [change]; an
/// override equal to the default is dropped.
McpServerConfig mcpWithTool(
  McpServerConfig config,
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

/// [o] with the given fields replaced (`risk` as a function to allow
/// setting `null`).
McpToolOverride mcpCopyOverride(
  McpToolOverride o, {
  bool? enabled,
  RiskLevel? Function()? risk,
  bool? autoRun,
}) => McpToolOverride(
  enabled: enabled ?? o.enabled,
  risk: risk == null ? o.risk : risk(),
  autoRun: autoRun ?? o.autoRun,
);

typedef _Choice = (String, String, McpToolOverride Function(McpToolOverride));

/// Level choices of one tool: only stricter than the server's (K8 b);
/// „ohne Nachfrage“ only for `write` tools (no undo).
List<_Choice> _choices(AppLocalizations l, RiskLevel base) => [
  if (base == RiskLevel.read) ...[
    (
      l.mcpToolNoAsk,
      l.mcpToolReadsOnly,
      (o) => mcpCopyOverride(o, risk: () => null),
    ),
    (
      l.mcpToolAlwaysAsk,
      l.mcpToolAlwaysAskHint,
      (o) => mcpCopyOverride(o, risk: () => RiskLevel.external),
    ),
  ],
  if (base == RiskLevel.write) ...[
    (
      l.mcpToolAlwaysAsk2,
      l.mcpToolDefaultNoUndo,
      (o) => mcpCopyOverride(o, autoRun: false),
    ),
    (
      l.mcpToolNoAsk2,
      l.mcpToolNoUndoNow,
      (o) => mcpCopyOverride(o, autoRun: true, risk: () => null),
    ),
  ],
];

/// Whether choice [i] of [_choices] is the current setting of a tool with
/// base level [base] and [override].
@visibleForTesting
bool mcpChoiceSelected(RiskLevel base, McpToolOverride? override, int i) =>
    switch ((base, i)) {
      (RiskLevel.read, 0) => override?.risk == null,
      (RiskLevel.read, _) => override?.risk != null,
      (RiskLevel.write, 0) =>
        !(override?.autoRun ?? false) || override?.risk != null,
      (RiskLevel.write, _) =>
        (override?.autoRun ?? false) && override?.risk == null,
      _ => false,
    };

/// Bottom sheet of one tool of [server]: description, effective level and
/// the level choices.
Future<void> showMcpToolSheet(
  BuildContext context,
  WidgetRef ref,
  McpServerView server,
  McpToolInfo tool,
) async {
  final source = ref.read(mcpServerSourceProvider);
  final config = server.config;
  final base = mcpBaseRisk(tool.annotations);
  final override = config.toolOverrides[tool.name];
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: WColors.surface,
    builder: (sheet) => _ToolSheet(
      tool: tool,
      config: config,
      mcpTool: server.offered[tool.name],
      choices: _choices(context.l10n, base),
      selected: (i) => mcpChoiceSelected(base, override, i),
      onPick: (change) {
        Navigator.of(sheet).pop();
        unawaited(
          guardMcp(
            context,
            () => source.update(mcpWithTool(config, tool.name, change)),
          ),
        );
      },
    ),
  );
}

class _ToolSheet extends StatelessWidget {
  const _ToolSheet({
    required this.tool,
    required this.config,
    required this.mcpTool,
    required this.choices,
    required this.selected,
    required this.onPick,
  });

  final McpToolInfo tool;
  final McpServerConfig config;
  final McpTool? mcpTool;
  final List<_Choice> choices;
  final bool Function(int index) selected;
  final void Function(McpToolOverride Function(McpToolOverride)) onPick;

  @override
  Widget build(BuildContext context) => SafeArea(
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
          Text(
            mcpAnnotationText(context.l10n, tool.annotations),
            style: WText.caption,
          ),
          Text(
            context.l10n.mcpToolEffective(
              mcpToolRiskText(context.l10n, tool, config),
            ),
            style: WText.label,
          ),
          if (config.confirmAll)
            Text(context.l10n.mcpToolConfirmAllOn, style: WText.caption)
          else if (choices.isEmpty)
            Text(context.l10n.mcpToolExternalAsks, style: WText.caption)
          else
            SectionCard(
              children: [
                for (final (i, (title, detail, change)) in choices.indexed)
                  SettingsRow(
                    title: title,
                    detail: detail,
                    onTap: () => onPick(change),
                    trailing: selected(i)
                        ? CheckStatusIcon(
                            CheckStatus.ok,
                            semanticLabel: context.l10n.selected,
                          )
                        : null,
                  ),
              ],
            ),
          if (mcpTool != null && mcpTool!.unsupportedSchemaParts.isNotEmpty)
            Text(
              context.l10n.mcpToolServerChecked(
                mcpTool!.unsupportedSchemaParts.join(', '),
              ),
              style: WText.caption,
            ),
        ],
      ),
    ),
  );
}
