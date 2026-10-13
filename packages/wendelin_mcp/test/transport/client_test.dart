import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

/// A bare HTTP server whose answers the test writes itself.
Future<HttpServer> rawServer(
  FutureOr<void> Function(HttpRequest req, String body) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    await handler(req, body);
  });
  return server;
}

Uri rawUrl(HttpServer s, [String path = '/mcp']) =>
    Uri.parse('http://127.0.0.1:${s.port}$path');

Map<String, Object?> rpc(String body) =>
    jsonDecode(body) as Map<String, Object?>;

Future<void> answer(
  HttpRequest req,
  Object? json, {
  int status = 200,
  String type = 'application/json',
  Map<String, String> headers = const {},
}) async {
  req.response.statusCode = status;
  req.response.headers.contentType = ContentType.parse('$type; charset=utf-8');
  headers.forEach(req.response.headers.set);
  req.response.write(json is String ? json : jsonEncode(json));
  await req.response.close();
}

Map<String, Object?> initResult(Object? id) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': {
    'protocolVersion': '2025-06-18',
    'capabilities': <String, Object?>{},
    'serverInfo': {'name': 'raw'},
  },
};

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

  Future<FakeMcpServer> fake({
    FakeTransportMode mode = FakeTransportMode.streamable,
    FakeResponseStyle style = FakeResponseStyle.json,
    FakeAuthMode auth = FakeAuthMode.none,
  }) async {
    final s = await FakeMcpServer.start(
      mode: mode,
      style: style,
      auth: auth,
      tools: [
        FakeMcpTool(
          'echo',
          handler: (args) => {
            'content': [
              {'type': 'text', 'text': jsonEncode(args)},
            ],
          },
        ),
      ],
    );
    cleanups.add(s.close);
    return s;
  }

  McpClient client(
    Uri url, {
    McpTransportKind transport = McpTransportKind.auto,
    McpAuth auth = const McpNoAuth(),
    McpSecrets? secrets,
    McpCacheStore? cache,
    Clock clock = const SystemClock(),
    McpTimeouts timeouts = const McpTimeouts(),
    McpLog? log,
  }) {
    final c = McpClient(
      config: McpServerConfig(
        id: 'srv',
        name: 'Server',
        slug: 'server',
        url: url,
        transport: transport,
        auth: auth,
      ),
      httpClient: httpClient,
      secrets: secrets ?? FakeMcpSecrets(),
      cache: cache,
      clock: clock,
      timeouts: timeouts,
      log: log,
    );
    cleanups.add(c.dispose);
    return c;
  }

  group('Streamable HTTP: Sitzung', () {
    test(
      'Mcp-Session-Id und MCP-Protocol-Version werden mitgeschickt',
      () async {
        final server = await fake();
        final c = client(server.url, transport: McpTransportKind.streamable);
        await c.callTool('echo', {'a': 1});
        final init = server.requests.firstWhere(
          (r) => r.rpcMethod == 'initialize',
        );
        expect(init.headers['mcp-session-id'], isNull);
        expect(init.headers['accept'], 'application/json, text/event-stream');
        final call = server.requests.firstWhere(
          (r) => r.rpcMethod == 'tools/call',
        );
        expect(server.sessions, contains(call.headers['mcp-session-id']));
        expect(call.headers['mcp-protocol-version'], mcpProtocolVersions.first);
        expect(c.serverInfo?.name, 'fake-mcp');
        expect(c.transport, McpTransportKind.streamable);
      },
    );

    test('404 nach Sitzungsablauf: neue Sitzung, Aufruf wiederholt', () async {
      final server = await fake();
      final c = client(server.url);
      await c.callTool('echo', const {});
      final first = server.sessions.single;
      server.expireSessions();
      final result = await c.callTool('echo', {'b': 2});
      expect(result.content.single['text'], '{"b":2}');
      expect(
        server.requests.where((r) => r.rpcMethod == 'initialize'),
        hasLength(2),
      );
      expect(server.sessions.single, isNot(first));
    });

    test(
      'Sitzung läuft zweimal hintereinander ab → Fehler statt Schleife',
      () async {
        var calls = 0;
        final raw = await rawServer((req, body) async {
          final m = rpc(body);
          if (m['method'] == 'initialize') {
            return answer(
              req,
              initResult(m['id']),
              headers: {'mcp-session-id': 's'},
            );
          }
          if (m['id'] == null) return answer(req, '', status: 202);
          calls++;
          return answer(req, 'gone', status: 404);
        });
        cleanups.add(() => raw.close(force: true));
        await expectLater(
          client(rawUrl(raw), transport: McpTransportKind.streamable).ping(),
          throwsA(
            isA<McpException>().having(
              (e) => e.kind,
              'kind',
              McpErrorKind.sessionExpired,
            ),
          ),
        );
        expect(calls, 2);
      },
    );

    test(
      'close() beendet die Sitzung mit DELETE, ohne Sitzung kein DELETE',
      () async {
        final server = await fake();
        final c = client(server.url);
        await c.close();
        expect(server.deletes, 0);
        await c.ping();
        await c.close();
        expect(server.deletes, 1);
        expect(server.sessions, isEmpty);
        await c.ping();
        expect(
          server.requests.where((r) => r.rpcMethod == 'initialize'),
          hasLength(2),
        );
      },
    );

    test('DELETE abgelehnt (405) ist kein Fehler', () async {
      final raw = await rawServer((req, body) async {
        if (req.method == 'DELETE') return answer(req, 'no', status: 405);
        final m = rpc(body);
        if (m['method'] == 'initialize') {
          return answer(
            req,
            initResult(m['id']),
            headers: {'mcp-session-id': 's'},
          );
        }
        if (m['id'] == null) return answer(req, '', status: 202);
        return answer(req, {
          'jsonrpc': '2.0',
          'id': m['id'],
          'result': <String, Object?>{},
        });
      });
      cleanups.add(() => raw.close(force: true));
      final logs = <String>[];
      final c = client(rawUrl(raw), log: logs.add);
      await c.ping();
      await c.close();
      expect(logs.join('\n'), contains('DELETE'));
    });

    test('JSON-Antwort als Batch: Benachrichtigung wird zugestellt', () async {
      final raw = await rawServer((req, body) async {
        final m = rpc(body);
        if (m['method'] == 'initialize') {
          return answer(req, initResult(m['id']));
        }
        if (m['id'] == null) return answer(req, '', status: 202);
        return answer(req, [
          {'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed'},
          {'jsonrpc': '2.0', 'id': m['id'], 'result': <String, Object?>{}},
        ]);
      });
      cleanups.add(() => raw.close(force: true));
      final c = client(rawUrl(raw));
      final changed = c.toolsChanged.first;
      await c.ping();
      await changed.timeout(const Duration(seconds: 2));
    });

    for (final (label, handler, kind)
        in <
          (
            String,
            Future<void> Function(HttpRequest, Map<String, Object?>),
            McpErrorKind,
          )
        >[
          (
            'unerwarteter Inhaltstyp',
            (req, m) => answer(req, '<html>', type: 'text/html'),
            McpErrorKind.protocol,
          ),
          (
            'Antwort mit falscher id',
            (req, m) => answer(req, {
              'jsonrpc': '2.0',
              'id': 999,
              'result': <String, Object?>{},
            }),
            McpErrorKind.protocol,
          ),
          (
            'SSE-Stream endet ohne Antwort',
            (req, m) => answer(
              req,
              'data: {"jsonrpc":"2.0","method":"notifications/x"}\n\n',
              type: 'text/event-stream',
            ),
            McpErrorKind.protocol,
          ),
          (
            'HTTP 500 mit Text',
            (req, m) => answer(req, 'kaputt\n  intern', status: 500),
            McpErrorKind.server,
          ),
          (
            'HTTP 401',
            (req, m) => answer(
              req,
              'no',
              status: 401,
              headers: {'www-authenticate': 'Bearer realm="x"'},
            ),
            McpErrorKind.authRequired,
          ),
        ]) {
      test('Fehlerfall: $label', () async {
        final raw = await rawServer((req, body) => handler(req, rpc(body)));
        cleanups.add(() => raw.close(force: true));
        final c = client(rawUrl(raw), transport: McpTransportKind.streamable);
        await expectLater(
          c.initialize(),
          throwsA(isA<McpException>().having((e) => e.kind, 'kind', kind)),
        );
        if (kind == McpErrorKind.authRequired) {
          expect(c.lastChallenge, 'Bearer realm="x"');
        }
        if (kind == McpErrorKind.server) {
          await expectLater(
            c.initialize(),
            throwsA(
              isA<McpException>()
                  .having(
                    (e) => e.message,
                    'message',
                    'Server-Fehler HTTP 500: kaputt intern',
                  )
                  .having((e) => e.retryable, 'retryable', isTrue),
            ),
          );
        }
      });
    }

    test(
      'Weiterleitung auf denselben Origin wird mit Methode verfolgt',
      () async {
        late HttpServer raw;
        raw = await rawServer((req, body) async {
          if (req.uri.path == '/mcp') {
            return answer(
              req,
              '',
              status: 307,
              headers: {'location': '/v2/mcp'},
            );
          }
          final m = rpc(body);
          if (m['method'] == 'initialize') {
            return answer(req, initResult(m['id']));
          }
          if (m['id'] == null) return answer(req, '', status: 202);
          return answer(req, {
            'jsonrpc': '2.0',
            'id': m['id'],
            'result': <String, Object?>{},
          });
        });
        cleanups.add(() => raw.close(force: true));
        await client(rawUrl(raw)).ping();
      },
    );

    test('Weiterleitung auf fremden Origin wird abgelehnt', () async {
      final raw = await rawServer(
        (req, body) => answer(
          req,
          '',
          status: 308,
          headers: {'location': 'http://192.168.99.99/mcp'},
        ),
      );
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw)).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.rejected,
          ),
        ),
      );
    });

    test('Weiterleitung ohne Location oder als Schleife', () async {
      final raw = await rawServer((req, body) async {
        if (req.uri.path == '/none') return answer(req, '', status: 302);
        return answer(req, '', status: 302, headers: {'location': '/mcp'});
      });
      cleanups.add(() => raw.close(force: true));
      for (final path in ['/none', '/mcp']) {
        await expectLater(
          client(
            rawUrl(raw, path),
            transport: McpTransportKind.streamable,
          ).ping(),
          throwsA(
            isA<McpException>().having(
              (e) => e.kind,
              'kind',
              McpErrorKind.protocol,
            ),
          ),
        );
      }
    });

    test('Verbindungszeitlimit bis zu den Headern', () async {
      final raw = await rawServer((req, body) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        await answer(req, '');
      });
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(
          rawUrl(raw),
          timeouts: const McpTimeouts(connect: Duration(milliseconds: 200)),
        ).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.timeout,
          ),
        ),
      );
    });
  });

  group('Transportwahl', () {
    test('auto erkennt Streamable HTTP', () async {
      final server = await fake();
      final c = client(server.url);
      expect(c.transport, isNull);
      final probe = await c.probe();
      expect(probe.status, McpReachability.reachable);
      expect(probe.transport, McpTransportKind.streamable);
      expect(probe.server?.name, 'fake-mcp');
      expect(probe.toString(), contains('reachable'));
    });

    test('auto fällt bei 405 auf Legacy-SSE zurück und bleibt dabei', () async {
      final server = await fake(mode: FakeTransportMode.legacySse);
      final c = client(server.url);
      await c.callTool('echo', const {});
      await c.callTool('echo', const {});
      expect(c.transport, McpTransportKind.sse);
      final posts = server.requests.where(
        (r) => r.method == 'POST' && r.uri.path == '/mcp',
      );
      expect(posts, hasLength(1));
      // Je Vorgang ein eigener SSE-Stream mit initialize (keine Dauerverbindung).
      expect(
        server.requests
            .where((r) => r.method == 'GET' && r.uri.path == '/mcp')
            .length,
        3,
      );
      for (var i = 0; i < 250 && server.sessions.isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(server.sessions, isEmpty);
    });

    test('auto ohne SSE-Endpunkt: ursprünglicher Fehler bleibt', () async {
      final raw = await rawServer(
        (req, body) => answer(req, 'nope', status: 404),
      );
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw)).ping(),
        throwsA(
          isA<McpException>()
              .having((e) => e.kind, 'kind', McpErrorKind.server)
              .having((e) => e.statusCode, 'status', 404),
        ),
      );
    });

    test('auto fällt auch bei 400 auf Legacy-SSE zurück', () async {
      final server = await fake(mode: FakeTransportMode.legacySse)
        ..legacyPostStatus = 400;
      final c = client(server.url);
      await c.ping();
      expect(c.transport, McpTransportKind.sse);
    });

    test('auto fällt bei 500 nicht zurück', () async {
      final methods = <String>[];
      final raw = await rawServer((req, body) {
        methods.add(req.method);
        return answer(req, 'x', status: 500);
      });
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw)).ping(),
        throwsA(isA<McpException>()),
      );
      expect(methods, ['POST']);
    });
  });

  group('Legacy-SSE: Fehlerfälle', () {
    test('Endpunkt auf fremdem Origin wird abgelehnt', () async {
      final server = await fake(mode: FakeTransportMode.legacySse)
        ..legacyEndpoint = 'http://192.168.99.99/messages';
      await expectLater(
        client(server.url, transport: McpTransportKind.sse).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.rejected,
          ),
        ),
      );
    });

    test('GET liefert kein SSE', () async {
      final raw = await rawServer((req, body) => answer(req, {'x': 1}));
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw), transport: McpTransportKind.sse).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.protocol,
          ),
        ),
      );
    });

    test('GET 401 → Anmeldung nötig', () async {
      final server = await fake(
        mode: FakeTransportMode.legacySse,
        auth: FakeAuthMode.bearer,
      );
      await expectLater(
        client(server.url, transport: McpTransportKind.sse).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.authRequired,
          ),
        ),
      );
    });

    test('Stream endet vor der Antwort', () async {
      final raw = await rawServer((req, body) async {
        if (req.method == 'GET') {
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write('event: endpoint\ndata: /messages\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await req.response.close();
          return;
        }
        await answer(req, 'Accepted', status: 202);
      });
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw), transport: McpTransportKind.sse).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.network,
          ),
        ),
      );
    });

    test('POST an den Endpunkt mit Fehlerstatus', () async {
      final server = await fake(mode: FakeTransportMode.legacySse);
      server.failNext.add(503);
      await expectLater(
        client(server.url, transport: McpTransportKind.sse).ping(),
        throwsA(isA<McpException>().having((e) => e.statusCode, 'status', 503)),
      );
    });

    test('Ungültige Nachricht im Stream', () async {
      final raw = await rawServer((req, body) async {
        if (req.method == 'GET') {
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write('event: endpoint\ndata: /messages\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          req.response.write('event: message\ndata: kein json\n\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(seconds: 2));
          await req.response.close();
          return;
        }
        await answer(req, 'Accepted', status: 202);
      });
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw), transport: McpTransportKind.sse).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.protocol,
          ),
        ),
      );
    });

    test('endlose data-Zeile ohne Leerzeile → zu groß', () async {
      final raw = await rawServer((req, body) async {
        if (req.method == 'GET') {
          req.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          req.response.write('event: endpoint\ndata: /messages\n\n');
          req.response.write('event: message\ndata: ');
          for (var i = 0; i < 200; i++) {
            try {
              req.response.write('x' * 1000);
              await req.response.flush();
            } on Object {
              return;
            }
          }
          await req.response.close();
          return;
        }
        await answer(req, 'Accepted', status: 202);
      });
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(
          rawUrl(raw),
          transport: McpTransportKind.sse,
          timeouts: const McpTimeouts(maxResponseBytes: 20000),
        ).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.tooLarge,
          ),
        ),
      );
    });

    test('Transport direkt: request ohne open', () async {
      final t = LegacySseTransport(
        Uri.parse('http://127.0.0.1:1/mcp'),
        McpTransportDeps(client: httpClient, headers: () async => const {}),
      );
      expect(t.perOperation, isTrue);
      expect(t.isOpen, isFalse);
      t.protocolVersion = 'egal';
      await expectLater(
        t.request('ping', null),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.protocol,
          ),
        ),
      );
      await t.close();
    });
  });

  group('Auth-Header', () {
    test(
      'Bearer: Header gesetzt, fehlendes Secret ohne Serverkontakt',
      () async {
        final server = await fake(auth: FakeAuthMode.bearer);
        final secrets = FakeMcpSecrets({'ref.bearer': server.bearerToken});
        final ok = client(
          server.url,
          auth: const McpBearerAuth('ref.bearer'),
          secrets: secrets,
        );
        await ok.ping();
        expect(
          server.requests.first.headers['authorization'],
          'Bearer ${server.bearerToken}',
        );
        final before = server.requests.length;
        await expectLater(
          client(server.url, auth: const McpBearerAuth('fehlt')).ping(),
          throwsA(
            isA<McpException>()
                .having((e) => e.kind, 'kind', McpErrorKind.authRequired)
                .having((e) => e.statusCode, 'status', isNull),
          ),
        );
        expect(server.requests.length, before);
      },
    );

    test('Bearer falsch → authRequired mit Challenge', () async {
      final server = await fake(auth: FakeAuthMode.bearer);
      final c = client(
        server.url,
        auth: const McpBearerAuth('r'),
        secrets: FakeMcpSecrets({'r': 'falsch'}),
      );
      final probe = await c.probe();
      expect(probe.status, McpReachability.authRequired);
      expect(c.lastChallenge, contains('Bearer'));
    });

    test('Eigene Header', () async {
      final server = await fake();
      await client(
        server.url,
        auth: McpHeadersAuth({'X-Api-Key': 'k1', 'X-Tenant': 'k2'}),
        secrets: FakeMcpSecrets({'k1': 'wert-eins', 'k2': 'wert-zwei'}),
      ).ping();
      expect(server.requests.first.headers['x-api-key'], 'wert-eins');
      expect(server.requests.first.headers['x-tenant'], 'wert-zwei');
    });

    test('OAuth ohne Flow → authRequired', () async {
      final server = await fake();
      await expectLater(
        client(
          server.url,
          auth: McpOAuth(tokenRef: 't', clientRef: 'c'),
        ).ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.authRequired,
          ),
        ),
      );
    });
  });

  group('Netzziel im Client', () {
    test('http ins Internet wird ohne Verbindung abgelehnt', () async {
      final c = client(Uri.parse('http://8.8.8.8/mcp'));
      await expectLater(
        c.ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.rejected,
          ),
        ),
      );
      final probe = await c.probe();
      expect(probe.status, McpReachability.unreachable);
      expect(probe.detail, contains('nicht erlaubt'));
    });

    test('geschlossener Port → nicht erreichbar (Netzfehler)', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final c = client(Uri.parse('http://127.0.0.1:$port/mcp'));
      await expectLater(
        c.ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.network,
          ),
        ),
      );
      expect((await c.probe()).status, McpReachability.unreachable);
    });

    test('kein MCP-Server → Protokollfehler', () async {
      final raw = await rawServer(
        (req, body) => answer(req, '<html>', type: 'text/html'),
      );
      cleanups.add(() => raw.close(force: true));
      final probe = await client(rawUrl(raw)).probe();
      expect(probe.status, McpReachability.protocolError);
    });
  });

  group('Tool-Liste und Cache', () {
    test('Cache mit Zeitstempel, Neuladen, Alter, Persistenz', () async {
      final server = await fake();
      final cache = InMemoryMcpCacheStore();
      final clock = FixedClock(DateTime.utc(2026, 10, 13, 8));
      final c = client(server.url, cache: cache, clock: clock);
      int lists() =>
          server.requests.where((r) => r.rpcMethod == 'tools/list').length;
      expect(await c.cachedTools(), isNull);
      expect((await c.listTools()).single.name, 'echo');
      expect(cache.entries['srv']!.fetchedAt, clock.now());
      await c.listTools();
      expect(lists(), 1);
      await c.listTools(refresh: true);
      expect(lists(), 2);
      clock.advance(const Duration(hours: 25));
      await c.listTools();
      expect(lists(), 3);
      // Neuer Client liest den gespeicherten Cache, ohne den Server zu fragen.
      final d = client(server.url, cache: cache, clock: clock);
      expect((await d.listTools()).single.name, 'echo');
      expect((await d.cachedTools())!.tools, hasLength(1));
      expect(lists(), 3);
    });

    test('list_changed macht den Cache ungültig', () async {
      final server = await fake(style: FakeResponseStyle.sse);
      final c = client(server.url);
      await c.listTools();
      server
        ..sendListChanged = true
        ..tools.add(FakeMcpTool('neu'));
      await c.callTool('echo', const {});
      server.sendListChanged = false;
      final tools = await c.listTools();
      expect(tools.map((t) => t.name), ['echo', 'neu']);
    });

    test('tools/list: ungültige Antworten', () async {
      for (final result in [
        <String, Object?>{},
        {'tools': 'x'},
      ]) {
        final raw = await rawServer((req, body) async {
          final m = rpc(body);
          if (m['method'] == 'initialize') {
            return answer(req, initResult(m['id']));
          }
          if (m['id'] == null) return answer(req, '', status: 202);
          return answer(req, {
            'jsonrpc': '2.0',
            'id': m['id'],
            'result': result,
          });
        });
        cleanups.add(() => raw.close(force: true));
        await expectLater(
          client(rawUrl(raw)).listTools(),
          throwsA(
            isA<McpException>().having(
              (e) => e.kind,
              'kind',
              McpErrorKind.protocol,
            ),
          ),
        );
      }
    });

    test('tools/list: höchstens maxListedTools Tools', () async {
      var page = 0;
      final raw = await rawServer((req, body) async {
        final m = rpc(body);
        if (m['method'] == 'initialize') {
          return answer(req, initResult(m['id']));
        }
        if (m['id'] == null) return answer(req, '', status: 202);
        page++;
        return answer(req, {
          'jsonrpc': '2.0',
          'id': m['id'],
          'result': {
            'tools': [
              for (var i = 0; i < 600; i++) {'name': 'p${page}_$i'},
            ],
            'nextCursor': 'weiter',
          },
        });
      });
      cleanups.add(() => raw.close(force: true));
      final tools = await client(rawUrl(raw)).listTools();
      expect(tools, hasLength(maxListedTools));
      expect(page, 2);
    });

    test('tools/list: endlose Paginierung wird abgebrochen', () async {
      final raw = await rawServer((req, body) async {
        final m = rpc(body);
        if (m['method'] == 'initialize') {
          return answer(req, initResult(m['id']));
        }
        if (m['id'] == null) return answer(req, '', status: 202);
        return answer(req, {
          'jsonrpc': '2.0',
          'id': m['id'],
          'result': {
            'tools': [
              {'name': 'x'},
              'kein objekt',
            ],
            'nextCursor': 'immer',
          },
        });
      });
      cleanups.add(() => raw.close(force: true));
      await expectLater(
        client(rawUrl(raw)).listTools(),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            contains('Seiten'),
          ),
        ),
      );
    });
  });

  test('Abbruch vor dem Start', () async {
    final server = await fake();
    final cancel = CancelToken()..cancel();
    await expectLater(
      client(server.url).ping(cancel: cancel),
      throwsA(
        isA<McpException>().having(
          (e) => e.kind,
          'kind',
          McpErrorKind.cancelled,
        ),
      ),
    );
    expect(server.requests, isEmpty);
  });
}
