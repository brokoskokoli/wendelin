// Test-MCP-Server auf dem Rechner für den Emulator (WP27, tool/e2e_mcp.sh).
//
//   cd app && dart run tool/mcp_test_server.dart [--token <bearer>]
//
// Lauscht nur auf 127.0.0.1 (der Emulator erreicht den Rechner unter
// 10.0.2.2, das ist dessen Loopback), gibt in der ersten Zeile
// `port=<port>` aus und läuft, bis stdin geschlossen wird. Bearer-Auth mit
// dem Token aus --token, sonst aus der Umgebungsvariable
// WENDELIN_MCP_TOKEN, sonst ein fester Testwert (kein Geheimnis).
// Tools: `get_state` (readOnlyHint), `delete_scene` (ohne Annotationen, also
// external) sowie `echo`, `get_time` (read), `toggle_light` (write) und
// `delete_thing` (destructiveHint) für die Routing- und Bestätigungstests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:wendelin_mcp/testing.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--token');
  final token = i >= 0 && i + 1 < args.length
      ? args[i + 1]
      : Platform.environment['WENDELIN_MCP_TOKEN'] ?? 'e2e-token';
  final server =
      await FakeMcpServer.start(
          publicHost: '10.0.2.2',
          auth: FakeAuthMode.bearer,
          tools: [
            FakeMcpTool(
              'get_state',
              description: 'Zustand eines Geräts lesen',
              annotations: const {'readOnlyHint': true},
              handler: (args) => {
                'content': [
                  {'type': 'text', 'text': '${args['entity']}: an'},
                ],
              },
            ),
            FakeMcpTool('delete_scene', description: 'Szene löschen'),
            FakeMcpTool(
              'echo',
              description: 'Text zurückgeben',
              annotations: const {'readOnlyHint': true},
              handler: (args) => {
                'content': [
                  {'type': 'text', 'text': '${args['text']}'},
                ],
              },
            ),
            FakeMcpTool(
              'get_time',
              description: 'Uhrzeit des Rechners lesen',
              annotations: const {'readOnlyHint': true},
              handler: (_) => {
                'content': [
                  {'type': 'text', 'text': DateTime.now().toIso8601String()},
                ],
              },
            ),
            FakeMcpTool(
              'toggle_light',
              description: 'Licht umschalten',
              annotations: const {
                'readOnlyHint': false,
                'destructiveHint': false,
              },
              handler: (_) => {
                'content': [
                  {'type': 'text', 'text': 'Licht umgeschaltet'},
                ],
              },
            ),
            FakeMcpTool(
              'delete_thing',
              description: 'Etwas löschen',
              annotations: const {'destructiveHint': true},
              handler: (_) => {
                'content': [
                  {'type': 'text', 'text': 'gelöscht'},
                ],
              },
            ),
          ],
        )
        ..bearerToken = token;
  stdout.writeln('port=${server.url.port}');
  // Home-Assistant-ähnliche REST-Schnittstelle für das HTTP-Tool (WP29):
  // GET /api/states/<entity> mit demselben Bearer-Token.
  var restRequests = 0;
  final rest = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  rest.listen((request) {
    restRequests++;
    final ok =
        request.headers.value('authorization') == 'Bearer $token' &&
        request.method == 'GET' &&
        request.uri.path.startsWith('/api/states/');
    request.response
      ..statusCode = ok ? 200 : 401
      ..headers.contentType = ContentType.json
      ..write(
        ok
            ? jsonEncode({
                'entity_id': request.uri.pathSegments.last,
                'state': 'on',
              })
            : '{"message":"nicht erlaubt"}',
      );
    unawaited(request.response.close());
  });
  stdout.writeln('http_port=${rest.port}');
  await stdin.drain<void>();
  stderr.writeln('Anfragen: ${server.requests.length}, REST: $restRequests');
  await rest.close(force: true);
  await server.close();
}
