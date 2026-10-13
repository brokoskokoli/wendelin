import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import 'client_test.dart' show answer, initResult, rawServer, rawUrl, rpc;

/// Raw MCP server that can simulate a restart: after [restart] every
/// request on a socket that was used before is cut off without an answer
/// (the old keep-alive sockets are dead); only new connections are served.
final class RestartableServer {
  RestartableServer._(this.server);

  static Future<RestartableServer> start({
    bool cutFirstToolCall = false,
  }) async {
    late RestartableServer self;
    var cutDone = !cutFirstToolCall;
    final server = await rawServer((req, body) async {
      final port = req.connectionInfo!.remotePort;
      if (self._dead.contains(port)) {
        self.cuts++;
        (await req.response.detachSocket(writeHeaders: false)).destroy();
        return;
      }
      self._seen.add(port);
      if (body.isEmpty) return answer(req, '', status: 204);
      final m = rpc(body);
      final method = m['method'] as String?;
      if (method == 'initialize') {
        return answer(
          req,
          initResult(m['id']),
          headers: {'mcp-session-id': 's'},
        );
      }
      if (m['id'] == null) return answer(req, '', status: 202);
      if (method == 'tools/call') {
        self.toolCalls++;
        if (!cutDone) {
          cutDone = true;
          (await req.response.detachSocket(writeHeaders: false)).destroy();
          return;
        }
      }
      return answer(req, {
        'jsonrpc': '2.0',
        'id': m['id'],
        'result': method == 'tools/call'
            ? {
                'content': [
                  {'type': 'text', 'text': 'ok'},
                ],
              }
            : <String, Object?>{},
      });
    });
    return self = RestartableServer._(server);
  }

  final HttpServer server;
  final Set<int> _seen = {};
  final Set<int> _dead = {};

  /// `tools/call` requests that reached the handler.
  int toolCalls = 0;

  /// Requests cut off because they came over a pre-restart socket.
  int cuts = 0;

  Uri get url => rawUrl(server);

  /// All sockets used so far are dead from now on.
  void restart() => _dead.addAll(_seen);
}

void main() {
  late http.Client httpClient;
  final cleanups = <Future<void> Function()>[];

  setUp(() => httpClient = http.Client());
  tearDown(() async {
    for (final c in cleanups.reversed) {
      await c();
    }
    cleanups.clear();
    httpClient.close();
  });

  Future<RestartableServer> start({bool cutFirstToolCall = false}) async {
    final s = await RestartableServer.start(cutFirstToolCall: cutFirstToolCall);
    cleanups.add(() => s.server.close(force: true));
    return s;
  }

  McpClient client(
    Uri url, {
    McpTimeouts timeouts = const McpTimeouts(idleCheck: Duration.zero),
    McpOAuthFlow? oauth,
    McpAuth auth = const McpNoAuth(),
    McpSecrets? secrets,
    McpTransportFactory? factory,
  }) {
    final c = McpClient(
      config: McpServerConfig(
        id: 'srv',
        name: 'Server',
        slug: 'server',
        url: url,
        transport: McpTransportKind.streamable,
        auth: auth,
      ),
      httpClient: httpClient,
      secrets: secrets ?? FakeMcpSecrets(),
      oauth: oauth,
      timeouts: timeouts,
      transportFactory: factory,
    );
    cleanups.add(c.dispose);
    return c;
  }

  ToolContext ctx() => ToolContext(
    sessionId: 's',
    clock: FixedClock(DateTime.utc(2026, 10, 13)),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
  );

  group('Server-Neustart (tote Keep-Alive-Sockets)', () {
    test(
      'schreibender Aufruf nach Neustart: ein tools/call, erfolgreich',
      () async {
        final s = await start();
        final c = client(s.url);
        await c.callTool('t', const {});
        expect(s.toolCalls, 1);

        s.restart();
        final result = await c.callTool('t', const {});

        expect(result.content.single['text'], 'ok');
        // Der Test des toten Sockets hat der ping übernommen.
        expect(s.cuts, greaterThan(0));
        expect(s.toolCalls, 2);
      },
    );

    test('mehrere Neustarts hintereinander', () async {
      final s = await start();
      final c = client(s.url);
      for (var i = 1; i <= 3; i++) {
        await c.callTool('t', const {});
        s.restart();
        expect(s.toolCalls, i);
      }
    });
  });

  group('Verbindungsabbruch im tools/call über McpTool.execute', () {
    // Der Server bricht den ersten tools/call ab (ohne Antwort).
    Future<({RestartableServer server, ToolOutcome outcome})> run(
      RiskLevel risk,
    ) async {
      final s = await start(cutFirstToolCall: true);
      final c = client(s.url, timeouts: const McpTimeouts());
      final tool = McpTool(
        integration: McpIntegration(client: c),
        info: const McpToolInfo(name: 't'),
        name: 'mcp_server__t',
        risk: risk,
      );
      final outcome = await tool.execute(const {}, ctx());
      return (server: s, outcome: outcome);
    }

    test('read: einmal wiederholt (2 Aufrufe)', () async {
      final r = await run(RiskLevel.read);
      expect(r.outcome.isError, isFalse);
      expect(r.server.toolCalls, 2);
    });

    test('write: genau ein Aufruf, Fehler', () async {
      final r = await run(RiskLevel.write);
      expect(r.outcome.isError, isTrue);
      expect(r.server.toolCalls, 1);
    });

    test('external: genau ein Aufruf, Fehler', () async {
      final r = await run(RiskLevel.external);
      expect(r.outcome.isError, isTrue);
      expect(r.server.toolCalls, 1);
    });
  });

  group('Auth-Wiederholung (Token abgelehnt)', () {
    test('nach dem Erneuern kein Wiederholen bei Netzfehler (write)', () async {
      final server = await FakeMcpServer.start(
        auth: FakeAuthMode.oauth,
        tools: [FakeMcpTool('t')],
      );
      cleanups.add(server.close);
      final secrets = FakeMcpSecrets();
      final config = McpServerConfig(
        id: 'o',
        name: 'O',
        slug: 'o',
        url: server.url,
        transport: McpTransportKind.streamable,
        auth: McpOAuth(tokenRef: 'o.tokens', clientRef: 'o.client'),
      );
      final flow = McpOAuthFlow(
        client: httpClient,
        secrets: secrets,
        browser: FakeAuthorizationBrowser(),
        redirectUri: Uri.parse('app.wendelin://oauth/mcp'),
      );
      await flow.authorize(config);

      // Der erste tools/call wird mit 401 abgelehnt, jeder weitere bricht mit
      // einem Netzfehler ab.
      final faulty = _FaultyClient(httpClient);
      final c = McpClient(
        config: config,
        httpClient: faulty,
        secrets: secrets,
        oauth: flow,
      );
      cleanups.add(c.dispose);

      await expectLater(
        c.callTool('t', const {}),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.network,
          ),
        ),
      );
      expect(faulty.toolCalls, 2);
    });
  });
}

/// Wraps [inner]: the first `tools/call` gets HTTP 401, later ones fail
/// like a broken connection.
final class _FaultyClient extends http.BaseClient {
  _FaultyClient(this.inner);

  final http.Client inner;
  int toolCalls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final body = request is http.Request ? request.body : '';
    if (!body.contains('"tools/call"')) return inner.send(request);
    toolCalls++;
    if (toolCalls == 1) {
      return Future.value(
        http.StreamedResponse(
          Stream.value(const <int>[]),
          401,
          headers: {'www-authenticate': 'Bearer'},
        ),
      );
    }
    throw http.ClientException('Verbindung getrennt');
  }
}
