import 'package:meta/meta.dart';

import 'protocol.dart';

/// Access to the secrets of MCP servers by reference (bearer tokens, header
/// values, OAuth tokens and client registrations). The app implements it on
/// top of its `SecretStore`; secrets never go into configuration JSON,
/// SQLite, logs or exports.
abstract interface class McpSecrets {
  /// The secret stored under [ref], or `null`.
  Future<String?> read(String ref);

  /// Stores [value] under [ref].
  Future<void> write(String ref, String value);

  /// Removes [ref] (no error if missing).
  Future<void> delete(String ref);
}

/// Opens the authorization page of an OAuth server and returns the URL the
/// browser was redirected to (starting with `redirect`). The app implements
/// it with Custom Tabs / the system browser (WP27).
abstract interface class AuthorizationBrowser {
  /// Shows [url] and completes with the redirect to [redirect] (carrying
  /// `code` and `state`, or `error`). Throws if the user aborts.
  Future<Uri> authorize(Uri url, Uri redirect);
}

/// Persistence of the cached tool list of each server (the app stores it,
/// e.g. in its settings database; contains no secrets).
abstract interface class McpCacheStore {
  /// The cached list of server [serverId], or `null`.
  Future<McpToolCache?> read(String serverId);

  /// Stores [cache] for [serverId].
  Future<void> write(String serverId, McpToolCache cache);

  /// Forgets the list of [serverId].
  Future<void> delete(String serverId);
}

/// A tool list with the time it was fetched.
@immutable
final class McpToolCache {
  /// Creates a cache entry.
  McpToolCache({required this.fetchedAt, required List<McpToolInfo> tools})
    : tools = List.unmodifiable(tools);

  /// Decodes [toJson]; throws [FormatException].
  factory McpToolCache.fromJson(Map<String, Object?> json) {
    final at = json['fetchedAt'];
    final tools = json['tools'];
    if (at is! String || tools is! List<Object?>) {
      throw const FormatException('McpToolCache: Felder fehlen');
    }
    return McpToolCache(
      fetchedAt: DateTime.parse(at),
      tools: [
        for (final t in tools)
          t is Map<String, Object?>
              ? McpToolInfo.fromJson(t)
              : throw const FormatException('McpToolCache: Tool'),
      ],
    );
  }

  /// When the list was loaded.
  final DateTime fetchedAt;

  /// The tools as the server described them.
  final List<McpToolInfo> tools;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'tools': [for (final t in tools) t.toJson()],
  };
}
