import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/mcp/mcp_persistence.dart';
import 'package:wendelin/di/mcp/mcp_providers.dart';
import 'package:wendelin/di/mcp/mcp_source.dart';
import 'package:wendelin/di/mcp/mcp_templates.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import 'test_env.dart';

/// Lets the tests talk to the in-process [FakeMcpServer]: the Flutter test
/// binding answers every `HttpClient` request with 400 by default.
void allowRealHttp() => HttpOverrides.global = null;

/// Tools of the test server: one per risk level.
List<FakeMcpTool> homeTools() => [
  FakeMcpTool(
    'get_state',
    description: 'Zustand eines Geräts lesen',
    inputSchema: const {
      'type': 'object',
      'properties': {
        'entity': {'type': 'string'},
      },
      'required': ['entity'],
    },
    annotations: const {'readOnlyHint': true},
    handler: (args) => {
      'content': [
        {'type': 'text', 'text': '${args['entity']}: an'},
      ],
    },
  ),
  FakeMcpTool(
    'set_light',
    description: 'Licht schalten',
    annotations: const {'destructiveHint': false},
  ),
  FakeMcpTool('delete_scene', description: 'Szene löschen'),
];

/// Overrides for MCP tests: [browser] for the OAuth login (default: one
/// that follows the fake server's consent at once); the debug log goes to
/// [log] (default: dropped).
List<Override> mcpOverrides({
  AuthorizationBrowser? browser,
  List<String>? log,
}) => [
  mcpAuthorizationBrowserProvider.overrideWithValue(
    browser ?? FakeAuthorizationBrowser(),
  ),
  mcpLogProvider.overrideWithValue(log?.add ?? (_) {}),
];

/// A draft for [server] named [name].
McpDraft draftFor(
  FakeMcpServer server, {
  String name = 'Homeserver',
  McpAuthKind auth = McpAuthKind.none,
  String? token,
  bool sensitive = false,
  bool confirmAll = false,
}) => McpDraft(
  name: name,
  url: server.url,
  auth: auth,
  token: token,
  sensitive: sensitive,
  confirmAll: confirmAll,
);

/// Adds [draft], switches the server on and waits until it is connected
/// and its tools are in the registry.
Future<McpServerView> addAndEnable(ProviderContainer c, McpDraft draft) async {
  await c.read(toolRegistryReadyProvider.future);
  final source = c.read(mcpServerSourceProvider);
  final view = await source.add(draft);
  final sync = c.read(userIntegrationSyncProvider);
  await sync.settled();
  await c
      .read(integrationActivatorProvider)
      .setEnabled(view.integrationId, enabled: true);
  // The switch triggers the connection (reload) in the background.
  await waitUntil(() => source.server(view.config.id)?.check != null);
  await source.reload(view.config.id);
  await sync.settled();
  return source.server(view.config.id)!;
}

/// Polls [condition] (real time) until it holds.
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Bedingung nicht erfüllt', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Tools as a server lists them (for seeded servers without network).
List<McpToolInfo> homeToolInfos() => [
  for (final t in homeTools()) McpToolInfo.fromJson(t.toJson()),
];

/// Stores servers as the app would after setting them up (configuration,
/// tool cache, last check, secrets), so screens show them without any
/// network. Servers whose integration id is in the environment's start
/// switches are switched on. Call before the container reads the source.
Future<void> seedServers(
  TestEnv env,
  List<({McpServerConfig config, List<McpToolInfo> tools, McpCheck? check})>
  servers, {
  Map<String, String> secrets = const {},
}) async {
  final settings = env.storage.settings;
  await settings.set(McpSettings.servers, [for (final s in servers) s.config]);
  for (final s in servers) {
    await settings.set(
      McpSettings.cache(s.config.id),
      McpToolCache(fetchedAt: env.clock.now(), tools: s.tools),
    );
    if (s.check case final check?) {
      await settings.set(McpSettings.check(s.config.id), check);
    }
  }
  for (final MapEntry(:key, :value) in secrets.entries) {
    await env.secrets.write(key, value);
  }
  // The sync restores the switches from the settings.
  for (final s in servers) {
    final id = s.config.integrationId;
    if (env.startup.enabledIntegrations.contains(id)) {
      await settings.set(AppSettings.integrationEnabled(id), true);
    }
  }
}
