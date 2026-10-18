import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'ha_server.dart';

Matcher _kind(PortErrorKind k) =>
    throwsA(isA<PortException>().having((e) => e.kind, 'kind', k));

void main() {
  late HaTestServer server;
  late FakeHaSecrets secrets;
  late HttpHaApi api;

  setUp(() async {
    server = await HaTestServer.start();
    secrets = FakeHaSecrets(HaEndpoint(url: server.url, token: server.token));
    api = HttpHaApi(secrets, timeout: const Duration(seconds: 3));
  });
  tearDown(() async {
    api.close();
    await server.close();
  });

  haApiContract(() async {
    final s = await HaTestServer.start();
    addTearDown(s.close);
    final a = HttpHaApi(FakeHaSecrets(HaEndpoint(url: s.url, token: s.token)));
    addTearDown(a.close);
    return a;
  }, name: 'HttpHaApi gegen nachgebautes Home Assistant');
  haApiContract(FakeHaApi.new, name: 'FakeHaApi');

  test('Token geht als Bearer, nie in der URL', () async {
    await api.check();
    expect(server.seen.single['authorization'], 'Bearer ${server.token}');
    expect(server.paths.single, 'GET /api/config');
    expect(server.fake.methodCalls, isEmpty);
  });

  test('check liest die Version', () async {
    server.fake.version = '2026.11.1';
    expect(await api.check(), '2026.11.1');
  });

  test('falsches Token: permissionDenied ohne Token im Text', () async {
    secrets.saved = HaEndpoint(url: server.url, token: 'falsch-geheim');
    await expectLater(
      api.states(),
      throwsA(
        isA<PortException>()
            .having((e) => e.kind, 'kind', PortErrorKind.permissionDenied)
            .having(
              (e) => '${e.message} $e',
              'Text',
              isNot(contains('geheim')),
            ),
      ),
    );
  });

  test('nicht eingerichtet: permissionDenied', () async {
    secrets.saved = null;
    await expectLater(api.check(), _kind(PortErrorKind.permissionDenied));
  });

  test('5xx und Verbindungsfehler: unavailable', () async {
    server.failWith.add(503);
    await expectLater(api.states(), _kind(PortErrorKind.unavailable));
    await server.close();
    await expectLater(api.states(), _kind(PortErrorKind.unavailable));
  });

  test(
    'Weiterleitung wird nicht gefolgt (Token bleibt bei der Adresse)',
    () async {
      server.failWith.add(302);
      await expectLater(api.states(), _kind(PortErrorKind.failed));
      expect(server.paths, ['GET /api/states']);
    },
  );

  test(
    'WebSocket folgt keiner Weiterleitung: kein Token an fremden Host',
    () async {
      final foreign = <String>[];
      final other = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => other.close(force: true));
      other.listen((r) async {
        foreign.add(r.uri.path);
        if (WebSocketTransformer.isUpgradeRequest(r)) {
          // ignore: close_sinks
          final ws = await WebSocketTransformer.upgrade(r);
          ws.add('{"type":"auth_required"}');
          ws.listen((m) => foreign.add('msg:$m'));
        } else {
          await r.response.close();
        }
      });
      server.socketRedirect = 'http://127.0.0.1:${other.port}/api/websocket';
      final list = await api.entities();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        list.singleWhere((e) => e.entityId == 'light.kitchen').area,
        isNull,
      );
      expect(foreign, isEmpty);
    },
  );

  group('WebSocket-Upgrade wird geprüft, bevor das Token fließt', () {
    // Raw server: REST answers `[]`, the WebSocket path answers [reply]
    // (given the request key) and records everything the client then sends.
    Future<List<int>> attempt(String Function(String key) reply) async {
      final received = <int>[];
      final raw = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(() => raw.close(force: true));
      raw.listen((r) async {
        if (r.uri.path == '/api/websocket') {
          final key = r.headers.value('sec-websocket-key') ?? '';
          // ignore: close_sinks
          final sock = await r.response.detachSocket(writeHeaders: false);
          sock.listen(received.addAll, onError: (Object _) {});
          sock.add(utf8.encode(reply(key)));
          await sock.flush();
          sock.add(utf8.encode('{"type":"auth_required"}'));
        } else {
          r.response
            ..headers.contentType = ContentType.json
            ..write('[]');
          await r.response.close();
        }
      });
      secrets.saved = HaEndpoint(
        url: 'http://127.0.0.1:${raw.port}',
        token: 'geheim',
      );
      expect(await api.entities(), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return received;
    }

    test('200 statt 101: kein Token', () async {
      final got = await attempt(
        (_) => 'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n',
      );
      expect(got, isEmpty);
    });

    test('101 mit falschem Sec-WebSocket-Accept: kein Token', () async {
      final got = await attempt(
        (_) =>
            'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
            'Connection: Upgrade\r\nSec-WebSocket-Accept: AAAAAAAAAAAAAAAAAAAAAAAAAAA=\r\n\r\n',
      );
      expect(got, isEmpty);
    });
  });

  test('HTML statt JSON und falsche Form: failed', () async {
    server.rawBody = '<html>Login</html>';
    await expectLater(api.states(), _kind(PortErrorKind.failed));
    server.rawBody = '{"a":1}';
    await expectLater(api.states(), _kind(PortErrorKind.failed));
  });

  test(
    'gespeicherte http-Adresse zu öffentlichem Host: nichts geht raus',
    () async {
      secrets.saved = const HaEndpoint(url: 'http://example.com', token: 't');
      await expectLater(api.states(), _kind(PortErrorKind.failed));
      expect(server.paths, isEmpty);
    },
  );

  test('ohne Admin-Recht: Namen ohne Räume', () async {
    server.registriesAllowed = false;
    final list = await api.entities();
    expect(list.singleWhere((e) => e.entityId == 'light.kitchen').area, isNull);
    expect(list.length, greaterThan(5));
  });
}
