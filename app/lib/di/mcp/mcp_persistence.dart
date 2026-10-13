import 'package:meta/meta.dart';
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

/// Result of the last explicit check of a server (on activation, „Neu
/// laden“, sign-in). The return to the app does not touch the network
/// (WP25 review) and shows this stored state instead.
@immutable
final class McpCheck {
  /// Creates a check result.
  const McpCheck({
    required this.at,
    required this.status,
    this.detail,
    this.latency,
    this.serverName,
    this.transport,
  });

  /// From a probe of the client at [at].
  factory McpCheck.fromProbe(McpProbeResult probe, DateTime at) => McpCheck(
    at: at,
    status: probe.status,
    detail: probe.detail,
    latency: probe.latency,
    serverName: switch (probe.server) {
      null => null,
      final s => [s.name, ?s.version].join(' '),
    },
    transport: probe.transport,
  );

  /// Decodes [toJson]; throws [FormatException].
  factory McpCheck.fromJson(Map<String, Object?> json) {
    final at = json['at'];
    final status = McpReachability.values
        .where((s) => s.name == json['status'])
        .firstOrNull;
    if (at is! String || status == null) {
      throw const FormatException('McpCheck: Felder fehlen');
    }
    final ms = json['latencyMs'];
    return McpCheck(
      at: DateTime.parse(at),
      status: status,
      detail: json['detail'] is String ? json['detail']! as String : null,
      latency: ms is int ? Duration(milliseconds: ms) : null,
      serverName: json['server'] is String ? json['server']! as String : null,
      transport: McpTransportKind.values
          .where((t) => t.name == json['transport'])
          .firstOrNull,
    );
  }

  /// When the check ran.
  final DateTime at;

  /// Outcome.
  final McpReachability status;

  /// German reason (already redacted by the client), if not reachable.
  final String? detail;

  /// How long the check took.
  final Duration? latency;

  /// Name and version the server reported.
  final String? serverName;

  /// Transport in use.
  final McpTransportKind? transport;

  /// Whether the server answered as an MCP server.
  bool get ok => status == McpReachability.reachable;

  /// JSON form (no secrets).
  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'status': status.name,
    'detail': ?detail,
    'latencyMs': ?latency?.inMilliseconds,
    'server': ?serverName,
    'transport': ?transport?.name,
  };
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
