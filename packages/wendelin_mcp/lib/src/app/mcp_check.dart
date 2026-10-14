import 'package:meta/meta.dart';

import '../client.dart';
import '../config.dart';

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
