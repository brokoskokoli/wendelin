import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import 'case_backends_m5.dart';

/// Fake backends of one case (WP29, `setup.backends`) and what to close
/// afterwards.
final class CaseBackends {
  CaseBackends._(this.integrations, this._cleanups);

  /// Starts the backends in [names] (see `caseBackends`).
  static Future<CaseBackends> start(Set<String> names, Clock clock) async {
    final integrations = <Integration>[];
    final cleanups = <Future<void> Function()>[];
    if (names.contains('bring')) integrations.add(await _bring());
    if (names.contains('http')) integrations.addAll(_http(clock));
    if (names.contains('mcp')) {
      integrations.add(await _mcp(cleanups));
    }
    if (names.contains('gtasks')) integrations.add(gtasksBackend(clock));
    if (names.contains('spotify')) {
      integrations.add(await spotifyBackend(clock));
    }
    if (names.contains('weather')) integrations.add(weatherBackend(clock));
    if (names.contains('station')) integrations.add(stationBackend());
    if (names.contains('notes')) integrations.add(notesBackend('de'));
    return CaseBackends._(integrations, cleanups);
  }

  /// Integrations to register.
  final List<Integration> integrations;

  final List<Future<void> Function()> _cleanups;

  /// Stops servers and clients.
  Future<void> close() async {
    for (final c in _cleanups.reversed) {
      await c();
    }
  }
}

/// Bring! with the contract state of `FakeBringApi` („Zuhause“ with Milch,
/// Äpfel and recently Brot; „Büro“ with Kaffee).
Future<Integration> _bring() async {
  final api = FakeBringApi();
  // As after the one-time login: only the session is stored.
  return BringIntegration(
    api,
    FakeBringSecrets(session: await api.login(api.email, api.password)),
  );
}

const _haHost = 'homeassistant.local';

/// Home-Assistant-like HTTP tools over a fake transport (no network).
List<Integration> _http(Clock clock) {
  final definitions = [
    HttpToolDefinition(
      id: 'ha-state',
      name: 'ha_get_state',
      description: 'Zustand einer Home-Assistant-Entität lesen (z. B. light.wohnzimmer).',
      method: HttpMethod.get,
      urlTemplate: 'http://$_haHost:8123/api/states/{entity_id}',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'entity_id': {'type': 'string'},
        },
        'required': ['entity_id'],
      },
      auth: const ApiKeyAuth('ha-token'),
      homeNetwork: true,
    ),
    HttpToolDefinition(
      id: 'ha-light-on',
      name: 'ha_light_on',
      description: 'Ein Licht in Home Assistant einschalten.',
      method: HttpMethod.post,
      urlTemplate: 'http://$_haHost:8123/api/services/light/turn_on',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'entity_id': {'type': 'string'},
        },
        'required': ['entity_id'],
      },
      bodyTemplate: const {'entity_id': '{entity_id}'},
      auth: const ApiKeyAuth('ha-token'),
      homeNetwork: true,
    ),
  ];
  final client = MockClient((request) async {
    final json = {
      'GET': {'entity_id': 'light.wohnzimmer', 'state': 'on'},
      'POST': [
        {'entity_id': 'light.wohnzimmer', 'state': 'on'},
      ],
    }[request.method];
    return http.Response(
      jsonEncode(json),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final runner = HttpToolRunner(
    transport: ClientHttpToolTransport(client),
    secrets: FakeHttpToolSecrets({'ha-token': 'eval-token'}),
    resolve: (_) async => [InternetAddress('192.168.178.20')],
    clock: clock,
  );
  return HttpToolsIntegration.all(definitions, runner);
}

/// An in-process MCP server „Home“ (`mcp_home__…`): `get_state` (read),
/// `toggle_light` (write), `delete_scene` (destructive).
Future<Integration> _mcp(List<Future<void> Function()> cleanups) async {
  Map<String, Object?> text(String t) => {
    'content': [
      {'type': 'text', 'text': t},
    ],
  };
  final server = await FakeMcpServer.start(
    tools: [
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
        handler: (args) => text('${args['entity']}: an'),
      ),
      FakeMcpTool(
        'toggle_light',
        description: 'Licht ein- oder ausschalten',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'room': {'type': 'string'},
          },
          'required': ['room'],
        },
        annotations: const {'readOnlyHint': false, 'destructiveHint': false},
        handler: (args) => text('Licht ${args['room']} umgeschaltet'),
      ),
      FakeMcpTool(
        'delete_scene',
        description: 'Szene löschen',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
          },
          'required': ['name'],
        },
        annotations: const {'destructiveHint': true},
        handler: (args) => text('Szene ${args['name']} gelöscht'),
      ),
    ],
  );
  cleanups.add(server.close);
  final client = McpClient(
    config: McpServerConfig(
      id: 'home-1',
      name: 'Home',
      slug: 'home',
      url: server.url,
    ),
    httpClient: http.Client(),
    secrets: FakeMcpSecrets(),
  );
  final integration = McpIntegration(client: client);
  cleanups
    ..add(client.dispose)
    ..add(integration.dispose);
  await integration.loadTools();
  return integration;
}
