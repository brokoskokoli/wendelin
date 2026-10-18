import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../../l10n/l10n.dart';

/// Effective level of tool [info] of [config] and whether it asks, e.g.
/// „ändert · fragt nach · kein Rückgängig“. MCP tools have no undo, so a
/// `write` tool asks unless the user allowed „ohne Nachfrage“.
String mcpToolRiskText(
  AppLocalizations l,
  McpToolInfo info,
  McpServerConfig config,
) {
  final override = config.toolOverrides[info.name];
  final base = mcpBaseRisk(info.annotations);
  final effective = mcpRisk(
    info.annotations,
    confirmAll: config.confirmAll,
    autoRun: override?.autoRun ?? false,
    override: override?.risk,
  );
  final kind = switch (base) {
    RiskLevel.read => l.mcpLabelsReads,
    RiskLevel.write => l.mcpLabelsChanges,
    RiskLevel.external => l.mcpLabelsExternal,
  };
  final asks = switch (effective) {
    RiskLevel.read => l.mcpLabelsNoAsk,
    RiskLevel.write => l.mcpLabelsNoAskNoUndo,
    RiskLevel.external when base == RiskLevel.write => l.mcpLabelsAsksNoUndo,
    RiskLevel.external => l.mcpLabelsAlwaysAsks,
  };
  return '$kind · $asks';
}

/// What the server says about tool [info] (its annotations are only a
/// hint, ADR 0010 §4).
String mcpAnnotationText(AppLocalizations l, McpToolAnnotations a) {
  if (a.readOnlyHint ?? false) return l.mcpLabelsHintReadOnly;
  return switch (a.destructiveHint) {
    false => l.mcpLabelsHintNonDestructive,
    true => l.mcpLabelsHintDestructive,
    null => l.mcpLabelsHintNone,
  };
}

/// Short local time of [at], e.g. „13.10. 08:12“.
String mcpTime(DateTime at) {
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
}

/// One line about the last check, e.g. „erreichbar · 13.10. 08:12 · 42 ms“.
String mcpCheckText(AppLocalizations l, McpCheck? check) {
  if (check == null) return l.mcpLabelsNotChecked;
  final what = switch (check.status) {
    McpReachability.reachable => 'erreichbar',
    McpReachability.authRequired => l.mcpLabelsAuthRequired,
    McpReachability.unreachable => l.mcpLabelsUnreachable,
    McpReachability.protocolError => l.mcpLabelsProtocolError,
  };
  return [
    what,
    mcpTime(check.at),
    if (check.latency case final l?) '${l.inMilliseconds} ms',
  ].join(' · ');
}

/// Result of a probe before saving, as one German line.
String mcpProbeText(
  AppLocalizations l,
  McpProbeResult probe, {
  required bool oauth,
}) => switch (probe.status) {
  McpReachability.reachable => [
    l.mcpLabelsReachable,
    if (probe.server case final s?) [s.name, ?s.version].join(' '),
    '${probe.latency.inMilliseconds} ms',
  ].join(' · '),
  McpReachability.authRequired =>
    oauth ? l.mcpLabelsAuthAfterSave : l.mcpLabelsAuthCheck,
  McpReachability.unreachable => l.mcpLabelsUnreachableDetail(
    probe.detail ?? '',
    l.mcpLabelsNetworkHint,
  ),
  McpReachability.protocolError => l.mcpLabelsProtocolErrorDetail(
    probe.detail ?? '',
  ),
};

/// How a server is shown in a list: the registry state, made more precise
/// by the last check (not reachable or not an MCP server count as error
/// with the reason; the tools stay offered, each call tries again).
({IntegrationStatus status, String? detail, String? action}) mcpTileState(
  AppLocalizations l,
  McpServerView server,
  IntegrationInfo? info,
) {
  final check = server.check;
  final oauth = server.config.auth is McpOAuth;
  final tools = server.integration.tools.length;
  final toolText = tools == 1 ? l.mcpLabelsOneTool : l.mcpLabelsTools(tools);
  if (info == null) {
    return (
      status: IntegrationStatus.available,
      detail: toolText,
      action: null,
    );
  }
  switch (info.status) {
    case IntegrationStatus.error:
      return (
        status: IntegrationStatus.error,
        detail: info.error,
        action: oauth ? l.mcpLabelsSignInAgain : l.mcpLabelsReplaceToken,
      );
    case IntegrationStatus.setupRequired:
      return (
        status: IntegrationStatus.setupRequired,
        detail: oauth
            ? l.mcpLabelsSignInMissing
            : l.mcpLabelsCredentialsMissing,
        action: oauth ? l.mcpLabelsSignIn : l.mcpLabelsSetUp,
      );
    case IntegrationStatus.active
        when check != null &&
            (check.status == McpReachability.unreachable ||
                check.status == McpReachability.protocolError):
      return (
        status: IntegrationStatus.error,
        detail: check.status == McpReachability.unreachable
            ? l.mcpLabelsUnreachableShort(l.mcpLabelsNetworkHint)
            : l.mcpLabelsProtocolErrorShort,
        action: l.mcpLabelsReload,
      );
    case IntegrationStatus.active:
      return (status: IntegrationStatus.active, detail: toolText, action: null);
    case IntegrationStatus.available || IntegrationStatus.unavailable:
      return (
        status: info.status,
        detail: info.availability.reason,
        action: null,
      );
  }
}
