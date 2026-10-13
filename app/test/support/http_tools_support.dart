import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/http_tools.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'test_env.dart';

/// Secret value that must never show up outside the `SecretStore`.
const httpCanary = 'kanarienvogel-http-4711';

/// Fake HTTP server for the tools: records requests, answers with
/// [respond]. Host names resolve to a public documentation address.
final class FakeHttpServer {
  /// Creates the server.
  FakeHttpServer({http.Response Function(http.Request request)? respond})
    : respond =
          respond ??
          ((_) => http.Response(
            '{"ok":true}',
            200,
            headers: {'content-type': 'application/json'},
          ));

  /// Answer for each request.
  http.Response Function(http.Request request) respond;

  /// Requests received.
  final List<http.Request> requests = [];

  /// Runner factory override using a `MockClient`.
  Override get override => httpToolRunnerFactoryProvider.overrideWithValue(
    (secrets) => HttpToolRunner(
      transport: ClientHttpToolTransport(
        MockClient((request) async {
          requests.add(request);
          return respond(request);
        }),
      ),
      secrets: secrets,
      resolve: (host) async => [InternetAddress('203.0.113.7')],
    ),
  );
}

/// A definition for tests (`https://api.example.org/…`).
HttpToolDefinition testHttpTool({
  String id = 'tool-1',
  String name = 'licht',
  HttpMethod method = HttpMethod.post,
  RiskLevel? risk,
  bool autoRun = false,
  bool sensitive = false,
  AuthMethod? auth,
}) => HttpToolDefinition(
  id: id,
  name: name,
  description: 'Schaltet das Licht',
  method: method,
  urlTemplate: 'https://api.example.org/licht/{raum}',
  inputSchema: const {
    'type': 'object',
    'properties': {
      'raum': {'type': 'string'},
    },
    'required': ['raum'],
  },
  bodyTemplate: method.allowsBody ? const {'an': true} : null,
  auth:
      auth ?? CustomHeadersAuth({'X-Api-Key': httpHeaderRef(id, 'X-Api-Key')}),
  risk: risk,
  autoRun: autoRun,
  sensitive: sensitive,
);

/// Stores [tools] (with [httpCanary] as secret of every secret header and
/// bearer token) and switches the HTTP integrations on.
Future<void> storeHttpTools(TestEnv env, List<HttpToolDefinition> tools) async {
  await env.storage.settings.set(httpToolsSetting, [
    for (final t in tools) t.toJson(),
  ]);
  for (final t in tools) {
    for (final ref in httpSecretRefs(t.auth)) {
      await env.secrets.write(
        SecretStoreHttpToolSecrets.keyOf(ref),
        httpCanary,
      );
    }
  }
  for (final id in [
    HttpToolsIntegration.plainId,
    HttpToolsIntegration.sensitiveId,
  ]) {
    await env.storage.settings.set(AppSettings.integrationEnabled(id), true);
  }
}
