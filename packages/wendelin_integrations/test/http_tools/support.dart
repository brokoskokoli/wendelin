import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Canary secret: must never show up anywhere visible.
const canary = 'kanarienvogel-geheim-4711';

/// Second canary with Base64-typical and quoting characters.
const canary2 = 'Zm9v+YmFy/YmF6=="ab cd';

/// Resolver for the HTTP-tool tests.
Future<List<InternetAddress>> testDns(String host) async => switch (host) {
  'api.example.org' ||
  'other.example.org' => [InternetAddress('93.184.216.34')],
  'rebind.example.org' => [InternetAddress('192.168.1.10')],
  'ha.local' => [InternetAddress('192.168.178.20')],
  _ => throw const SocketException('NXDOMAIN'),
};

/// A GET definition against `api.example.org`.
HttpToolDefinition def({
  String name = 'status',
  HttpMethod method = HttpMethod.get,
  String url = 'https://api.example.org/items/{id}?q={q}',
  Map<String, Object?>? schema,
  Map<String, String> headers = const {},
  Object? body,
  HttpBodyFormat bodyFormat = HttpBodyFormat.json,
  AuthMethod auth = const ApiKeyAuth('tok'),
  RiskLevel? risk,
  bool sensitive = false,
  bool homeNetwork = false,
  bool enabled = true,
  Duration timeout = const Duration(seconds: 15),
  String? responsePath,
  bool autoRun = false,
}) => HttpToolDefinition(
  id: 'id-$name',
  name: name,
  description: 'Testtool $name',
  method: method,
  urlTemplate: url,
  inputSchema:
      schema ??
      {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'q': {'type': 'string'},
          'level': {'type': 'integer'},
          'room': {'type': 'string'},
        },
        'required': ['id'],
      },
  headers: headers,
  bodyTemplate: body,
  bodyFormat: bodyFormat,
  auth: auth,
  risk: risk,
  sensitive: sensitive,
  homeNetwork: homeNetwork,
  enabled: enabled,
  timeout: timeout,
  responsePath: responsePath,
  autoRun: autoRun,
);

/// Requests seen by [mockRunner]'s client.
final class Recorder {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];
}

/// Runner with a `MockClient` answering via [handler].
({HttpToolRunner runner, Recorder rec, FakeHttpToolSecrets secrets}) mockRunner(
  Future<http.Response> Function(http.Request request) handler, {
  Map<String, String> secrets = const {'tok': canary},
  int maxBytes = 256 * 1024,
  Clock? clock,
}) {
  final rec = Recorder();
  final fakeSecrets = FakeHttpToolSecrets(secrets);
  final client = MockClient((request) async {
    rec.requests.add(request);
    rec.bodies.add(request.body);
    return handler(request);
  });
  return (
    runner: HttpToolRunner(
      transport: ClientHttpToolTransport(client),
      secrets: fakeSecrets,
      resolve: testDns,
      maxResponseBytes: maxBytes,
      clock: clock ?? FixedClock(DateTime.utc(2026, 10, 13)),
    ),
    rec: rec,
    secrets: fakeSecrets,
  );
}

/// JSON response helper.
http.Response jsonResponse(String body, {int status = 200}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
