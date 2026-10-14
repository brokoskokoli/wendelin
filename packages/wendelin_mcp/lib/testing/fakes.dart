import 'dart:async';
import 'dart:io';

import '../src/app/mcp_app_ports.dart';
import '../src/app/mcp_check.dart';
import '../src/config.dart';
import '../src/ports.dart';

/// [McpSecrets] in memory; records every write (to check that tokens land
/// only here).
final class FakeMcpSecrets implements McpSecrets {
  /// Creates the store with [initial] values.
  FakeMcpSecrets([Map<String, String> initial = const {}])
    : values = Map.of(initial);

  /// Current values by reference.
  final Map<String, String> values;

  /// References written, in order.
  final List<String> writes = [];

  /// Reads that should fail (simulated keystore error).
  bool failReads = false;

  @override
  Future<String?> read(String ref) async {
    if (failReads) throw StateError('Secret-Speicher nicht verfügbar');
    return values[ref];
  }

  @override
  Future<void> write(String ref, String value) async {
    writes.add(ref);
    values[ref] = value;
  }

  @override
  Future<void> delete(String ref) async => values.remove(ref);
}

/// [McpCacheStore] in memory.
final class InMemoryMcpCacheStore implements McpCacheStore {
  /// Stored entries by server id.
  final Map<String, McpToolCache> entries = {};

  @override
  Future<McpToolCache?> read(String serverId) async => entries[serverId];

  @override
  Future<void> write(String serverId, McpToolCache cache) async =>
      entries[serverId] = cache;

  @override
  Future<void> delete(String serverId) async => entries.remove(serverId);
}

/// [AuthorizationBrowser] without a browser: requests the authorization URL
/// with `dart:io` (as the user's browser would, the fake server consents
/// at once) and returns the redirect `Location`. [tamper] may change the
/// redirect (wrong `state`, error) for negative tests.
final class FakeAuthorizationBrowser implements AuthorizationBrowser {
  /// Creates the browser.
  FakeAuthorizationBrowser({this.tamper, this.fail = false});

  /// Changes the redirect before it is returned.
  final Uri Function(Uri redirect)? tamper;

  /// Whether the user „closes the browser“ (throws).
  final bool fail;

  /// Authorization URLs opened, in order.
  final List<Uri> opened = [];

  @override
  Future<Uri> authorize(Uri url, Uri redirect) async {
    opened.add(url);
    if (fail) throw StateError('Browser geschlossen');
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) {
        throw StateError('Keine Weiterleitung (HTTP ${response.statusCode})');
      }
      final back = Uri.parse(location);
      return tamper?.call(back) ?? back;
    } finally {
      client.close(force: true);
    }
  }
}

/// [McpConfigStore] in memory.
final class FakeMcpConfigStore implements McpConfigStore {
  /// Creates the store with [initial] servers.
  FakeMcpConfigStore([List<McpServerConfig> initial = const []])
    : stored = [...initial];

  /// The stored servers.
  List<McpServerConfig> stored;

  /// The stored checks by server id.
  final Map<String, McpCheck> checks = {};

  @override
  Future<List<McpServerConfig>> servers() async => [...stored];

  @override
  Future<void> saveServers(List<McpServerConfig> servers) async =>
      stored = [...servers];

  @override
  Future<McpCheck?> check(String serverId) async => checks[serverId];

  @override
  Future<void> saveCheck(String serverId, McpCheck check) async =>
      checks[serverId] = check;

  @override
  Future<void> deleteCheck(String serverId) async => checks.remove(serverId);
}

/// An [McpAuditSink] that records its entries.
final class FakeMcpAudit {
  /// The entries written, in order.
  final List<({McpAuditKind kind, DateTime at, Map<String, Object?> payload})>
  entries = [];

  /// Set to make the sink fail.
  bool fail = false;

  /// The sink to hand to the source.
  Future<void> call(
    McpAuditKind kind,
    DateTime at,
    Map<String, Object?> payload,
  ) async {
    if (fail) throw StateError('Audit nicht verfügbar');
    entries.add((kind: kind, at: at, payload: payload));
  }
}
