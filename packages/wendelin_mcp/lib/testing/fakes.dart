import 'dart:async';
import 'dart:io';

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
