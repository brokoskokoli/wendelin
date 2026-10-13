import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

/// Kanarienwert: darf nirgends außer im Secret-Speicher und im Header
/// auftauchen.
const canary = 'CANARY-7f3a9c1e5b2d';

void main() {
  late http.Client httpClient;
  late HttpServer echo;
  final logs = <String>[];

  setUp(() async {
    httpClient = http.Client();
    logs.clear();
    // Ein Server, der alle Header (also auch das Secret) im Fehlertext
    // zurückspiegelt – der schlimmste Fall.
    echo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((req) async {
      await utf8.decoder.bind(req).join();
      final headers = StringBuffer();
      req.headers.forEach((k, v) => headers.write('$k=${v.join()} '));
      req.response.statusCode = 500;
      req.response.write('Fehler, Anfrage war: $headers');
      await req.response.close();
    });
  });

  tearDown(() async {
    httpClient.close();
    await echo.close(force: true);
  });

  for (final (label, auth, secrets) in [
    (
      'Bearer',
      const McpBearerAuth('ref.bearer') as McpAuth,
      {'ref.bearer': canary},
    ),
    (
      'eigene Header',
      McpHeadersAuth({'X-Api-Key': 'ref.key'}),
      {'ref.key': canary},
    ),
  ]) {
    test('$label: kein Secret in Exception, toString, Export, Log', () async {
      final config = McpServerConfig(
        id: 'c',
        name: 'Echo',
        slug: 'echo',
        url: Uri.parse('http://127.0.0.1:${echo.port}/mcp'),
        auth: auth,
      );
      final client = McpClient(
        config: config,
        httpClient: httpClient,
        secrets: FakeMcpSecrets(secrets),
        log: logs.add,
      );
      Object? caught;
      try {
        await client.ping();
      } on McpException catch (e) {
        caught = e;
      }
      expect(caught, isA<McpException>());
      expect(caught.toString(), contains('***'));
      expect(caught.toString(), isNot(contains(canary)));
      expect((caught! as McpException).message, isNot(contains(canary)));

      final probe = await client.probe();
      expect(probe.detail, isNot(contains(canary)));
      expect(probe.toString(), isNot(contains(canary)));

      final integration = McpIntegration(client: client);
      final tool = integration.buildTools([
        const McpToolInfo(name: 't'),
      ]).single;
      final outcome = await tool.execute(
        const {},
        ToolContext(
          sessionId: 's',
          clock: const SystemClock(),
          locale: 'de-DE',
          timeZone: 'Europe/Berlin',
        ),
      );
      expect(outcome.text, isNot(contains(canary)));
      expect(outcome.toString(), isNot(contains(canary)));

      expect(jsonEncode(config.toJson()), isNot(contains(canary)));
      expect(config.toString(), isNot(contains(canary)));
      expect(auth.toString(), isNot(contains(canary)));
      expect(logs, isNotEmpty);
      expect(logs.join('\n'), isNot(contains(canary)));
      expect(client.redact('x $canary y'), 'x *** y');
      await integration.dispose();
      await client.dispose();
    });
  }

  test('OAuth: Tokens nur in den Secrets, nie in Log, Export, Cache', () async {
    final server = await FakeMcpServer.start(
      auth: FakeAuthMode.oauth,
      tools: [FakeMcpTool('t')],
    );
    addTearDown(server.close);
    final secrets = FakeMcpSecrets();
    final cache = InMemoryMcpCacheStore();
    final config = McpServerConfig(
      id: 'o',
      name: 'O',
      slug: 'o',
      url: server.url,
      auth: McpOAuth(tokenRef: 'o.tokens', clientRef: 'o.client'),
    );
    final flow = McpOAuthFlow(
      client: httpClient,
      secrets: secrets,
      browser: FakeAuthorizationBrowser(),
      redirectUri: Uri.parse('app.wendelin://oauth/mcp'),
      random: Random(1),
      log: logs.add,
    );
    final client = McpClient(
      config: config,
      httpClient: httpClient,
      secrets: secrets,
      oauth: flow,
      cache: cache,
      log: logs.add,
    );
    final tokens = await flow.authorize(config);
    await client.listTools();
    final secretValues = [tokens.accessToken, tokens.refreshToken!];
    final places = [
      logs.join('\n'),
      jsonEncode(config.toJson()),
      jsonEncode(cache.entries['o']!.toJson()),
      tokens.toString(),
      config.auth.toString(),
    ];
    for (final value in secretValues) {
      for (final place in places) {
        expect(place, isNot(contains(value)));
      }
    }
    expect(secrets.values['o.tokens'], contains(tokens.accessToken));
    expect(secrets.writes.toSet(), {'o.client', 'o.tokens'});
    await client.dispose();
  });
}
