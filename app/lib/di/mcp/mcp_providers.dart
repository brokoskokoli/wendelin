import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../../platform/channel_authorization_browser.dart';
import '../providers.dart';
import 'mcp_secrets.dart';
import 'mcp_source.dart';

/// Shows the OAuth login (Custom Tabs; fake in tests).
final mcpAuthorizationBrowserProvider = Provider<AuthorizationBrowser>(
  (ref) => const ChannelAuthorizationBrowser(),
);

/// Whether a browser for the OAuth login is installed.
final mcpBrowserAvailableProvider = Provider<Future<bool> Function()>((ref) {
  final browser = ref.watch(mcpAuthorizationBrowserProvider);
  return browser is ChannelAuthorizationBrowser
      ? browser.isAvailable
      : () async => true;
});

/// Debug log of the MCP clients (debug builds only). The clients remove
/// every secret they sent; lines hold method, address, status and cleaned
/// error texts, never headers or bodies.
final mcpLogProvider = Provider<McpLog?>(
  (ref) => kDebugMode ? (line) => debugPrint(line) : null,
);

/// The MCP servers (WP27) as source of user-defined integrations.
///
/// Switching a server on connects it (`initialize`, `tools/list`); the
/// return to the app does not (WP25 review).
final mcpServerSourceProvider = Provider<McpServerSource>((ref) {
  final storage = ref.watch(storageProvider);
  final source = McpServerSource(
    settings: storage.settings,
    secrets: SecretStoreMcpSecrets(ref.watch(secretStoreProvider)),
    httpClient: ref.watch(httpClientProvider),
    browser: ref.watch(mcpAuthorizationBrowserProvider),
    browserAvailable: ref.watch(mcpBrowserAvailableProvider),
    ids: ref.watch(idGeneratorProvider),
    clock: ref.watch(clockProvider),
    audit: storage.audit,
    // Read lazily: the registry is rebuilt (e.g. after a „sensibel“ mark).
    reportError: (id, message) {
      try {
        ref.read(toolRegistryProvider).reportError(id, message);
      } on ArgumentError {
        // Not registered (yet): the status shows the check instead.
      }
    },
    log: ref.watch(mcpLogProvider),
  );
  ref.listen<Set<String>>(enabledIntegrationsProvider, (previous, next) {
    for (final id in next.difference(previous ?? const {})) {
      final server = source.byIntegrationId(id);
      if (server != null) unawaited(source.reload(server.config.id));
    }
  });
  ref.onDispose(source.dispose);
  return source;
});
