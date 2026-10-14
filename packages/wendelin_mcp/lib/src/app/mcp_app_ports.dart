import '../config.dart';
import 'mcp_check.dart';

/// Persistence of the MCP configuration (the app keeps it in its
/// settings). Holds no secrets: the configurations only carry secret
/// references.
abstract interface class McpConfigStore {
  /// All configured servers (`McpServerConfig.toJson`, secret references
  /// only). The on/off switch of a server is *not* part of it (one source
  /// of truth: the app's integration switch).
  Future<List<McpServerConfig>> servers();

  /// Replaces the configured servers.
  Future<void> saveServers(List<McpServerConfig> servers);

  /// The last explicit check of [serverId]; `null` if there is none or it
  /// cannot be read.
  Future<McpCheck?> check(String serverId);

  /// Stores the last check of [serverId].
  Future<void> saveCheck(String serverId, McpCheck check);

  /// Forgets the check of [serverId].
  Future<void> deleteCheck(String serverId);
}

/// Kind of an [McpAuditSink] entry.
enum McpAuditKind {
  /// A successful check.
  verification,

  /// A failed check or an authentication error.
  error,
}

/// Writes an audit entry (the app maps it to its audit log, which redacts
/// secret-looking fields). Failures are the sink's business: the source
/// logs them and carries on.
typedef McpAuditSink = Future<void> Function(
  McpAuditKind kind,
  DateTime at,
  Map<String, Object?> payload,
);
