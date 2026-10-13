// Test-MCP-Server auf dem Rechner für den Emulator (WP27, tool/e2e_mcp.sh).
//
//   cd app && dart run tool/mcp_test_server.dart [--token <bearer>]
//
// Lauscht nur auf 127.0.0.1 (der Emulator erreicht den Rechner unter
// 10.0.2.2, das ist dessen Loopback), gibt in der ersten Zeile
// `port=<port>` aus und läuft, bis stdin geschlossen wird. Bearer-Auth mit
// dem Token aus --token (Standard: ein fester Testwert, kein Geheimnis),
// zwei Tools: `get_state` (readOnlyHint) und `delete_scene` (ohne
// Annotationen, also external).
import 'dart:io';

import 'package:wendelin_mcp/testing.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--token');
  final token = i >= 0 && i + 1 < args.length ? args[i + 1] : 'e2e-token';
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
          ],
        )
        ..bearerToken = token;
  stdout.writeln('port=${server.url.port}');
  await stdin.drain<void>();
  stderr.writeln('Anfragen: ${server.requests.length}');
  await server.close();
}
