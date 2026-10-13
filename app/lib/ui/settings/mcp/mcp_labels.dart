import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../../../di/mcp/mcp_persistence.dart';
import '../../../di/mcp/mcp_source.dart';

/// Hint when a server cannot be reached (concept: „Netzwerk“).
const mcpUnreachableHint = 'Tailscale/WireGuard aktiv?';

/// Effective level of tool [info] of [config] and whether it asks, e.g.
/// „ändert · fragt nach · kein Rückgängig“. MCP tools have no undo, so a
/// `write` tool asks unless the user allowed „ohne Nachfrage“.
String mcpToolRiskText(McpToolInfo info, McpServerConfig config) {
  final override = config.toolOverrides[info.name];
  final base = mcpBaseRisk(info.annotations);
  final effective = mcpRisk(
    info.annotations,
    confirmAll: config.confirmAll,
    autoRun: override?.autoRun ?? false,
    override: override?.risk,
  );
  final kind = switch (base) {
    RiskLevel.read => 'liest',
    RiskLevel.write => 'ändert',
    RiskLevel.external => 'Außenwirkung',
  };
  final asks = switch (effective) {
    RiskLevel.read => 'ohne Nachfrage',
    RiskLevel.write => 'ohne Nachfrage · kein Rückgängig',
    RiskLevel.external when base == RiskLevel.write =>
      'fragt nach · kein Rückgängig',
    RiskLevel.external => 'fragt immer nach',
  };
  return '$kind · $asks';
}

/// What the server says about tool [info] (its annotations are only a
/// hint, ADR 0010 §4).
String mcpAnnotationText(McpToolAnnotations a) {
  if (a.readOnlyHint ?? false) return 'Server: nur lesend (readOnlyHint)';
  return switch (a.destructiveHint) {
    false => 'Server: ändert, nicht destruktiv (destructiveHint: false)',
    true => 'Server: destruktiv (destructiveHint)',
    null => 'Server: keine Angabe – gilt als Außenwirkung',
  };
}

/// Short local time of [at], e.g. „13.10. 08:12“.
String mcpTime(DateTime at) {
  final t = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}. ${two(t.hour)}:${two(t.minute)}';
}

/// One line about the last check, e.g. „erreichbar · 13.10. 08:12 · 42 ms“.
String mcpCheckText(McpCheck? check) {
  if (check == null) return 'Noch nicht geprüft';
  final what = switch (check.status) {
    McpReachability.reachable => 'erreichbar',
    McpReachability.authRequired => 'Anmeldung nötig',
    McpReachability.unreachable => 'nicht erreichbar',
    McpReachability.protocolError => 'kein gültiger MCP-Server',
  };
  return [
    what,
    mcpTime(check.at),
    if (check.latency case final l?) '${l.inMilliseconds} ms',
  ].join(' · ');
}

/// Result of a probe before saving, as one German line.
String mcpProbeText(McpProbeResult probe, {required bool oauth}) =>
    switch (probe.status) {
      McpReachability.reachable => [
        'Erreichbar',
        if (probe.server case final s?) [s.name, ?s.version].join(' '),
        '${probe.latency.inMilliseconds} ms',
      ].join(' · '),
      McpReachability.authRequired =>
        oauth
            ? 'Anmeldung nötig – nach dem Speichern anmelden'
            : 'Anmeldung nötig – Token oder Header prüfen',
      McpReachability.unreachable =>
        'Nicht erreichbar: ${probe.detail ?? ''}. $mcpUnreachableHint',
      McpReachability.protocolError =>
        'Kein gültiger MCP-Server: ${probe.detail ?? ''}',
    };

/// How a server is shown in a list: the registry state, made more precise
/// by the last check (not reachable or not an MCP server count as error
/// with the reason; the tools stay offered, each call tries again).
({IntegrationStatus status, String? detail, String? action}) mcpTileState(
  McpServerView server,
  IntegrationInfo? info,
) {
  final check = server.check;
  final oauth = server.config.auth is McpOAuth;
  final tools = server.integration.tools.length;
  final toolText = tools == 1 ? '1 Tool' : '$tools Tools';
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
        action: oauth ? 'Neu anmelden' : 'Token ersetzen',
      );
    case IntegrationStatus.setupRequired:
      return (
        status: IntegrationStatus.setupRequired,
        detail: oauth ? 'Anmeldung fehlt' : 'Zugangsdaten fehlen',
        action: oauth ? 'Anmelden' : 'Einrichten',
      );
    case IntegrationStatus.active
        when check != null &&
            (check.status == McpReachability.unreachable ||
                check.status == McpReachability.protocolError):
      return (
        status: IntegrationStatus.error,
        detail: check.status == McpReachability.unreachable
            ? 'Nicht erreichbar · $mcpUnreachableHint'
            : 'Kein gültiger MCP-Server',
        action: 'Neu laden',
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
