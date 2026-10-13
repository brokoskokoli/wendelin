import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'bring_server.dart';

Matcher _port(PortErrorKind kind, [Object? message]) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', message ?? anything),
);

const _email = 'kontrakt@example.org';
const _pw = 'kanarien-passwort';

void main() {
  late BringServer server;
  late List<String> log;
  late HttpBringApi api;

  setUp(() {
    server = BringServer();
    log = [];
    api = server.api(log: log.add);
  });

  group('Anfragen', () {
    test('Login: Formular, Kopfzeilen, Felder der Antwort', () async {
      final auth = await api.login(_email, _pw);
      final req = server.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(), 'https://api.getbring.com/rest/v2/bringauth');
      expect(req.bodyFields, {'email': _email, 'password': _pw});
      expect(req.headers['X-BRING-API-KEY'], bringPublicApiKey);
      expect(req.headers['X-BRING-CLIENT'], 'android');
      expect(req.headers['X-BRING-APPLICATION'], 'bring');
      expect(req.headers['X-BRING-COUNTRY'], 'DE');
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(auth.userUuid, '00000000-0000-4000-8000-000000000001');
      expect(auth.publicUuid, '00000000-0000-4000-8000-000000000002');
      expect(auth.defaultListUuid, '00000000-0000-4000-8000-0000000000a1');
      expect(auth.refreshToken, isNotNull);
    });

    test('authentisierte Aufrufe tragen Token und Nutzer-Ids', () async {
      final auth = await api.login(_email, _pw);
      await api.lists(auth);
      final req = server.requests.last;
      expect(
        req.url.path,
        '/rest/bringusers/00000000-0000-4000-8000-000000000001/lists',
      );
      expect(req.headers['Authorization'], 'Bearer ${auth.accessToken}');
      expect(req.headers['X-BRING-USER-UUID'], auth.userUuid);
      expect(req.headers['X-BRING-PUBLIC-USER-UUID'], auth.publicUuid);
    });

    test('Änderungen als JSON mit Operation und Mengenangabe', () async {
      final auth = await api.login(_email, _pw);
      const list = '00000000-0000-4000-8000-0000000000a1';
      await api.saveItem(
        auth,
        list,
        const BringItem(name: 'Milch', spec: '2 Liter', uuid: 'u1'),
      );
      await api.completeItem(auth, list, const BringItem(name: 'Milch'));
      await api.removeItem(
        auth,
        list,
        const BringItem(name: 'Brot', spec: 'x'),
      );
      final puts = server.requests.where((r) => r.method == 'PUT').toList();
      expect(puts, hasLength(3));
      expect(puts.first.url.path, '/rest/v2/bringlists/$list/items');
      expect(
        puts.first.headers['Content-Type'],
        startsWith('application/json'),
      );
      final changes = [
        for (final r in puts)
          ((jsonDecode(r.body) as Map)['changes'] as List).single as Map,
      ];
      expect(changes[0], {
        'accuracy': '0.0',
        'altitude': '0.0',
        'latitude': '0.0',
        'longitude': '0.0',
        'itemId': 'Milch',
        'spec': '2 Liter',
        'uuid': 'u1',
        'operation': 'TO_PURCHASE',
      });
      expect(changes[1]['operation'], 'TO_RECENTLY');
      expect(changes[1].containsKey('uuid'), isFalse);
      expect(changes[2]['operation'], 'REMOVE');
      expect(changes[2]['spec'], '');
    });

    test('refresh behält das alte Refresh-Token ohne neues', () async {
      final auth = await api.login(_email, _pw);
      server.refreshWithoutNewToken = true;
      final fresh = await api.refresh(auth);
      expect(fresh.refreshToken, auth.refreshToken);
      expect(fresh.accessToken, isNot(auth.accessToken));
      final req = server.requests.last;
      expect(req.url.path, '/rest/v2/bringauth/token');
      expect(req.bodyFields['grant_type'], 'refresh_token');
    });

    test('eigene Basis-URL mit Pfad, Land', () async {
      final seen = <http.Request>[];
      final custom = HttpBringApi(
        baseUrl: Uri.parse('https://proxy.example.org/bring/rest/'),
        country: 'CH',
        client: MockClient((r) async {
          seen.add(r);
          return http.Response('{"lists": []}', 200);
        }),
      );
      await custom.lists(const BringAuth(userUuid: 'u', accessToken: 't'));
      expect(
        seen.single.url.toString(),
        'https://proxy.example.org/bring/rest/bringusers/u/lists',
      );
      expect(seen.single.headers['X-BRING-COUNTRY'], 'CH');
      expect(
        seen.single.headers.containsKey('X-BRING-PUBLIC-USER-UUID'),
        false,
      );
    });

    test('fehlende Listen- oder Artikelfelder optional: leer', () async {
      final auth = await api.login(_email, _pw);
      server.next.add(canned(200, '{"uuid": "x", "items": {}}'));
      final items = await api.items(auth, 'x');
      expect(items.purchase, isEmpty);
      expect(items.recently, isEmpty);
    });
  });

  group('Fehler', () {
    late BringAuth auth;
    setUp(() async => auth = await api.login(_email, _pw));

    test('Login abgelehnt (401 und 400)', () async {
      await expectLater(
        api.login(_email, 'falsch'),
        _port(PortErrorKind.permissionDenied, contains('Passwort falsch')),
      );
      server.next.add(canned(400, '{}'));
      await expectLater(
        api.login(_email, _pw),
        _port(PortErrorKind.permissionDenied),
      );
    });

    test('401/403 bei Aufrufen: permissionDenied', () async {
      server.next.add(canned(403, '{}'));
      await expectLater(api.lists(auth), _port(PortErrorKind.permissionDenied));
      server.expireTokens();
      await expectLater(api.lists(auth), _port(PortErrorKind.permissionDenied));
    });

    test('400 außerhalb des Logins: failed', () async {
      server.next.add(canned(400, '{}'));
      await expectLater(api.lists(auth), _port(PortErrorKind.failed));
    });

    test('404: notFound', () async {
      await expectLater(
        api.items(auth, 'gibt-es-nicht'),
        _port(PortErrorKind.notFound, contains('Liste nicht gefunden')),
      );
      server.next.add(canned(404));
      await expectLater(api.lists(auth), _port(PortErrorKind.notFound));
    });

    for (final status in [500, 502, 503]) {
      test('$status: unavailable', () async {
        server.next.add(canned(status, bringFixture('maintenance.html')));
        await expectLater(
          api.items(auth, 'x'),
          _port(PortErrorKind.unavailable, contains('Serverfehler')),
        );
      });
    }

    test('HTML statt JSON: failed', () async {
      server.next.add(
        canned(200, bringFixture('maintenance.html'), {
          'content-type': 'text/html',
        }),
      );
      await expectLater(
        api.lists(auth),
        _port(PortErrorKind.failed, contains('unerwartete Antwort')),
      );
    });

    test('fehlende Felder und andere Typen: failed', () async {
      server.next.add(canned(200, bringFixture('items_missing_fields.json')));
      await expectLater(api.items(auth, 'x'), _port(PortErrorKind.failed));
      server.next.add(canned(200, bringFixture('lists_wrong_types.json')));
      await expectLater(api.lists(auth), _port(PortErrorKind.failed));
      server.next.add(canned(200, bringFixture('login_missing_token.json')));
      await expectLater(api.login(_email, _pw), _port(PortErrorKind.failed));
      server.next.add(canned(200, '[]'));
      await expectLater(api.lists(auth), _port(PortErrorKind.failed));
      server.next.add(canned(200, '{"items": {"purchase": "Milch"}}'));
      await expectLater(api.items(auth, 'x'), _port(PortErrorKind.failed));
      server.next.add(
        canned(200, '{"items": {"purchase": [{"itemId": "M", "uuid": 3}]}}'),
      );
      await expectLater(api.items(auth, 'x'), _port(PortErrorKind.failed));
      server.next.add(
        canned(200, '{"lists": [{"listUuid": "", "name": "a"}]}'),
      );
      await expectLater(api.lists(auth), _port(PortErrorKind.failed));
      server.next.add(canned(200, '{"access_token": 5}'));
      await expectLater(api.refresh(auth), _port(PortErrorKind.failed));
    });

    test('ungültiges UTF-8: failed', () async {
      final bad = HttpBringApi(
        client: MockClient(
          (_) async => http.Response.bytes([0x7b, 0xff, 0xfe, 0x7d], 200),
        ),
      );
      await expectLater(bad.lists(auth), _port(PortErrorKind.failed));
    });

    test('andere Statuscodes (302, 418): failed', () async {
      server.next
        ..add(canned(302))
        ..add(canned(418));
      await expectLater(api.lists(auth), _port(PortErrorKind.failed));
      await expectLater(
        api.saveItem(auth, 'x', const BringItem(name: 'a')),
        _port(PortErrorKind.failed, contains('418')),
      );
    });

    test('Zeitüberschreitung: unavailable', () async {
      final slow = HttpBringApi(
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) => Completer<http.Response>().future),
      );
      await expectLater(
        slow.lists(auth),
        _port(PortErrorKind.unavailable, contains('Zeitüberschreitung')),
      );
    });

    test(
      'nicht erreichbar (ClientException, SocketException): unavailable',
      () async {
        for (final error in <Object>[
          http.ClientException('weg'),
          const SocketException('weg'),
        ]) {
          final down = HttpBringApi(
            client: MockClient((_) async => throw error),
          );
          await expectLater(
            down.lists(auth),
            _port(PortErrorKind.unavailable, contains('nicht erreichbar')),
          );
        }
      },
    );

    test('andere Ausnahmen des Clients laufen durch', () async {
      final broken = HttpBringApi(
        client: MockClient((_) async => throw StateError('Bug')),
      );
      await expectLater(broken.lists(auth), throwsStateError);
    });
  });

  group('Anfragelimit', () {
    late FixedClock clock;
    late HttpBringApi limited;
    late BringAuth auth;

    setUp(() async {
      clock = FixedClock(DateTime.utc(2026, 10, 13, 12));
      limited = HttpBringApi(client: server.client, clock: clock, log: log.add);
      auth = await limited.login(_email, _pw);
    });

    test('429 sperrt bis Retry-After, ohne Anfrage zu senden', () async {
      server.next.add(canned(429, '', {'retry-after': '120'}));
      await expectLater(
        limited.saveItem(auth, 'x', const BringItem(name: 'Milch')),
        _port(PortErrorKind.unavailable, contains('Anfragelimit')),
      );
      final sent = server.requests.length;
      clock.advance(const Duration(seconds: 119));
      await expectLater(
        limited.lists(auth),
        _port(PortErrorKind.unavailable, contains('Anfragelimit')),
      );
      expect(server.requests, hasLength(sent));
      expect(log.last, contains('gesperrt'));
      clock.advance(const Duration(seconds: 1));
      expect(await limited.lists(auth), hasLength(2));
      expect(server.requests, hasLength(sent + 1));
    });

    test('ohne oder mit unlesbarem Retry-After: 60 s', () async {
      server.next.add(canned(429, '', {'retry-after': 'bald'}));
      await expectLater(limited.lists(auth), _port(PortErrorKind.unavailable));
      clock.advance(const Duration(seconds: 59));
      await expectLater(limited.lists(auth), _port(PortErrorKind.unavailable));
      clock.advance(const Duration(seconds: 1));
      expect(await limited.lists(auth), isNotEmpty);
    });

    test('Retry-After höchstens 30 min', () async {
      server.next.add(canned(429, '', {'retry-after': '999999'}));
      await expectLater(limited.lists(auth), _port(PortErrorKind.unavailable));
      clock.advance(const Duration(minutes: 30));
      expect(await limited.lists(auth), isNotEmpty);
    });

    test('kein automatisches Wiederholen', () async {
      server.next.add(canned(429));
      final before = server.requests.length;
      await expectLater(
        limited.saveItem(auth, 'x', const BringItem(name: 'Milch')),
        _port(PortErrorKind.unavailable),
      );
      expect(server.requests.length, before + 1);
      server.next.add(canned(503));
      clock.advance(const Duration(minutes: 1));
      await expectLater(
        limited.saveItem(auth, 'x', const BringItem(name: 'Milch')),
        _port(PortErrorKind.unavailable),
      );
      expect(server.requests.length, before + 2);
    });
  });

  test(
    'Log: nur Operation und Status, keine Ids, Tokens, Passwörter',
    () async {
      final auth = await api.login(_email, _pw);
      await api.lists(auth);
      await api.items(auth, '00000000-0000-4000-8000-0000000000a1');
      await api.saveItem(
        auth,
        '00000000-0000-4000-8000-0000000000a1',
        const BringItem(name: 'Milch'),
      );
      await expectLater(api.login(_email, 'falsch'), throwsA(anything));
      expect(log, [
        'Bring! login → 200',
        'Bring! lists → 200',
        'Bring! items → 200',
        'Bring! to_purchase → 204',
        'Bring! login → 401',
      ]);
      final all = log.join('\n');
      for (final secret in [
        _pw,
        auth.accessToken,
        auth.refreshToken!,
        auth.userUuid,
        'Milch',
      ]) {
        expect(all, isNot(contains(secret)));
      }
    },
  );
}
