import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Settings keys of the MCP servers (WP27). Only configuration without
/// secrets, the cached tool lists and the result of the last check.
abstract final class McpSettings {
  /// All configured servers (`McpServerConfig.toJson`, secret references
  /// only). The switch of a server is `AppSettings.integrationEnabled`,
  /// not `McpServerConfig.enabled` (one source of truth).
  static final servers = SettingKey<List<McpServerConfig>>(
    'mcp.servers',
    encode: (servers) => [for (final s in servers) s.toJson()],
    decode: (json) {
      if (json is! List) throw const FormatException('mcp.servers: Liste');
      return [
        for (final e in json)
          e is Map<String, Object?>
              ? McpServerConfig.fromJson(e)
              : throw const FormatException('mcp.servers: Eintrag'),
      ];
    },
    defaultValue: const [],
  );

  /// Cached tool list of server [serverId].
  static SettingKey<McpToolCache> cache(String serverId) => SettingKey(
    'mcp.$serverId.tools',
    encode: (c) => c.toJson(),
    decode: (json) => json is Map<String, Object?>
        ? McpToolCache.fromJson(json)
        : throw const FormatException('mcp tools: Objekt'),
  );

  /// Last explicit check of server [serverId].
  static SettingKey<McpCheck> check(String serverId) => SettingKey(
    'mcp.$serverId.check',
    encode: (c) => c.toJson(),
    decode: (json) => json is Map<String, Object?>
        ? McpCheck.fromJson(json)
        : throw const FormatException('mcp check: Objekt'),
  );
}

/// [McpCacheStore] in the settings database (the tool list holds no
/// secrets).
final class SettingsMcpCacheStore implements McpCacheStore {
  /// Creates the store over [settings].
  const SettingsMcpCacheStore(this.settings);

  /// The settings repository.
  final SettingsRepository settings;

  @override
  Future<McpToolCache?> read(String serverId) async {
    try {
      return await settings.get(McpSettings.cache(serverId));
    } on FormatException {
      // A broken cache is no error: the list is loaded again.
      return null;
    }
  }

  @override
  Future<void> write(String serverId, McpToolCache cache) =>
      settings.set(McpSettings.cache(serverId), cache);

  @override
  Future<void> delete(String serverId) =>
      settings.remove(McpSettings.cache(serverId));
}

/// [McpConfigStore] in the settings database (`mcp.servers`, one check
/// per server; no secrets).
final class SettingsMcpConfigStore implements McpConfigStore {
  /// Creates the store over [settings].
  const SettingsMcpConfigStore(this.settings);

  /// The settings repository.
  final SettingsRepository settings;

  @override
  Future<List<McpServerConfig>> servers() async =>
      await settings.get(McpSettings.servers) ?? const [];

  @override
  Future<void> saveServers(List<McpServerConfig> servers) =>
      settings.set(McpSettings.servers, servers);

  @override
  Future<McpCheck?> check(String serverId) async {
    try {
      return await settings.get(McpSettings.check(serverId));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveCheck(String serverId, McpCheck check) =>
      settings.set(McpSettings.check(serverId), check);

  @override
  Future<void> deleteCheck(String serverId) =>
      settings.remove(McpSettings.check(serverId));
}

/// [McpAuditSink] on the audit log.
McpAuditSink auditLogMcpSink(AuditLogRepository audit) =>
    (kind, at, payload) => audit.record(
      AuditEntry(
        at: at,
        kind: switch (kind) {
          McpAuditKind.verification => AuditKind.verification,
          McpAuditKind.error => AuditKind.error,
        },
        payload: payload,
      ),
    );
