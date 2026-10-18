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
