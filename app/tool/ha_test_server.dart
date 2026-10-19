// Fake-Home-Assistant auf dem Rechner für den Emulator (WP91, tool/e2e_ha.sh).
//
//   cd app && dart run tool/ha_test_server.dart --token <token>
//
// Lauscht nur auf 127.0.0.1 (Emulator: 10.0.2.2), gibt `port=<port>` aus und
// schreibt je Anfrage eine Zeile `req <Methode> <Pfad>` nach stderr (nie
// Token oder Body). Läuft, bis stdin geschlossen wird.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../packages/wendelin_integrations/test/home_assistant/ha_server.dart';

Future<void> main(List<String> args) async {
  final i = args.indexOf('--token');
  final token = i >= 0 && i + 1 < args.length ? args[i + 1] : 'e2e-token';
  final server = await HaTestServer.start(token: token);
  final port = Uri.parse(server.url).port;
  stdout.writeln('port=$port');
  var logged = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    while (logged < server.paths.length) {
      stderr.writeln('req ${server.paths[logged++]}');
    }
  });
  await stdin.transform(utf8.decoder).drain<void>();
  timer.cancel();
  await server.close();
}
