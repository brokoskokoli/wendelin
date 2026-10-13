import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support.dart';

void main() {
  group('Ausführung mit MockClient', () {
    test('Erfolg: URL, Methode, Header, Bearer-Secret, JSON-Text', () async {
      final m = mockRunner((_) async => jsonResponse('{"ok":true}'));
      final r = await m.runner.call(def(headers: {'X-Room': '{room}'}), {
        'id': 'a b',
        'q': 'x&y',
        'room': 'kitchen',
      });
      expect(r.isError, isFalse);
      expect(r.status, 200);
      expect(r.contentType, 'application/json');
      expect(r.text, '{"ok":true}');
      final sent = m.rec.requests.single;
      expect(sent.method, 'GET');
      expect(
        sent.url.toString(),
        'https://api.example.org/items/a%20b?q=x%26y',
      );
      expect(sent.headers['Authorization'], 'Bearer $canary');
      expect(sent.headers['X-Room'], 'kitchen');
      expect(sent.headers['Accept'], contains('application/json'));
      expect(r.request!.headers['Authorization'], redactedSecret);
      expect(r.request!.url, sent.url);
      expect(r.finalUrl, sent.url);
    });

    test('POST mit JSON-Body typgerecht und Content-Type', () async {
      final m = mockRunner((_) async => http.Response('', 204));
      final r = await m.runner.call(
        def(
          method: HttpMethod.post,
          url: 'https://api.example.org/api/services/light/turn_on',
          body: {'entity_id': '{id}', 'brightness': '{level}'},
        ),
        {'id': 'light.kitchen', 'level': 128},
      );
      expect(r.isError, isFalse);
      expect(r.text, '');
      expect(jsonDecode(m.rec.bodies.single), {
        'entity_id': 'light.kitchen',
        'brightness': 128,
      });
      expect(
        m.rec.requests.single.headers['Content-Type'],
        'application/json; charset=utf-8',
      );
      expect(r.request!.body, '{"entity_id":"light.kitchen","brightness":128}');
    });

    test('Formular-Body', () async {
      final m = mockRunner((_) async => http.Response('ok', 200));
      await m.runner.call(
        def(
          method: HttpMethod.put,
          url: 'https://api.example.org/form',
          body: {'id': '{id}', 'n': 1},
          bodyFormat: HttpBodyFormat.form,
        ),
        {'id': 'ä&b'},
      );
      expect(m.rec.bodies.single, 'id=%C3%A4%26b&n=1');
      expect(
        m.rec.requests.single.headers['Content-Type'],
        startsWith('application/x-www-form-urlencoded'),
      );
    });

    test('ApiKeyAuth mit eigenem Header und CustomHeadersAuth', () async {
      final m = mockRunner(
        (_) async => http.Response('ok', 200),
        secrets: {'tok': canary, 'h1': 'wert-eins-111', 'h2': 'wert-zwei-222'},
      );
      await m.runner.call(
        def(auth: const ApiKeyAuth('tok', headerName: 'X-N8n-Key')),
        {'id': '1'},
      );
      expect(m.rec.requests.last.headers['X-N8n-Key'], canary);
      expect(m.rec.requests.last.headers.containsKey('Authorization'), isFalse);
      final r = await m.runner.call(
        def(auth: CustomHeadersAuth({'X-A': 'h1', 'X-B': 'h2'})),
        {'id': '1'},
      );
      expect(m.rec.requests.last.headers['X-A'], 'wert-eins-111');
      expect(m.rec.requests.last.headers['X-B'], 'wert-zwei-222');
      expect(r.request!.headers['X-A'], redactedSecret);
      await m.runner.call(def(auth: const NoAuth()), {'id': '1'});
      expect(m.rec.requests.last.headers.containsKey('Authorization'), isFalse);
    });

    for (final (status, reason) in [
      (400, 'Bad Request'),
      (401, 'Unauthorized'),
      (404, 'Not Found'),
      (500, 'Internal Server Error'),
      (503, 'Service Unavailable'),
    ]) {
      test('HTTP $status → Fehler mit Status und Ausschnitt', () async {
        final m = mockRunner(
          (_) async => http.Response(
            'Fehlerdetails ${'x' * 1000}',
            status,
            reasonPhrase: reason,
          ),
        );
        final r = await m.runner.call(def(), {'id': '1'});
        expect(r.isError, isTrue);
        expect(r.error, isNull);
        expect(r.status, status);
        expect(r.reason, reason);
        expect(r.text, startsWith('Fehlerdetails'));
      });
    }

    test('Zeitlimit', () async {
      final m = mockRunner((_) => Completer<http.Response>().future);
      final r = await m.runner.call(def(timeout: const Duration(seconds: 1)), {
        'id': '1',
      });
      expect(r.isError, isTrue);
      expect(r.error, contains('Zeitüberschreitung'));
      expect(r.error, contains('1 s'));
      expect(r.request, isNotNull);
    });

    test('zu große Antwort wird abgeschnitten und markiert', () async {
      final m = mockRunner(
        (_) async => http.Response('a' * 5000, 200),
        maxBytes: 1024,
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.isError, isFalse);
      expect(r.truncated, isTrue);
      expect(r.text.length, 1024);
    });

    test('zu große Antwort mit responsePath → Fehler', () async {
      final m = mockRunner(
        (_) async => jsonResponse('{"a":"${'x' * 5000}"}'),
        maxBytes: 1024,
      );
      final r = await m.runner.call(def(responsePath: 'a'), {'id': '1'});
      expect(r.isError, isTrue);
      expect(r.truncated, isTrue);
      expect(r.error, contains('größer als 1 KB'));
    });

    for (final mime in [
      'image/png',
      'application/octet-stream',
      'audio/mpeg',
    ]) {
      test('Nicht-Text-Antwort ($mime) abgelehnt', () async {
        final m = mockRunner(
          (_) async => http.Response.bytes(
            [0x89, 0x50, 0x4e, 0x47],
            200,
            headers: {'content-type': mime},
          ),
        );
        final r = await m.runner.call(def(), {'id': '1'});
        expect(r.isError, isTrue);
        expect(r.error, contains('„$mime“ wird nicht unterstützt'));
      });
    }

    test('Nicht-Text bei Status 500 → Fehler über Status', () async {
      final m = mockRunner(
        (_) async => http.Response.bytes(
          [1, 2],
          500,
          headers: {'content-type': 'image/png'},
        ),
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.isError, isTrue);
      expect(r.status, 500);
      expect(r.error, isNull);
    });

    for (final mime in [
      'text/plain',
      'text/html',
      'application/xml',
      'application/problem+json',
      'application/atom+xml',
      '',
    ]) {
      test('Text-Antwort „$mime“ erlaubt', () async {
        final m = mockRunner(
          (_) async => http.Response(
            'inhalt',
            200,
            headers: {if (mime.isNotEmpty) 'content-type': mime},
          ),
        );
        final r = await m.runner.call(def(), {'id': '1'});
        expect(r.isError, isFalse);
        expect(r.text, 'inhalt');
      });
    }

    test('Latin-1-Antwort wird dekodiert', () async {
      final m = mockRunner(
        (_) async => http.Response.bytes(
          latin1.encode('Grüße'),
          200,
          headers: {'content-type': 'text/plain; charset=ISO-8859-1'},
        ),
      );
      expect((await m.runner.call(def(), {'id': '1'})).text, 'Grüße');
    });

    group('responsePath', () {
      const answer =
          '{"state":"on","attributes":{"brightness":128,'
          '"friendly_name":"Küche"},"list":[{"n":"a"},{"n":"b"}]}';
      final cases = <String, String?>{
        'state': 'on',
        'attributes.brightness': '128',
        'attributes.friendly_name': 'Küche',
        'attributes': '{"brightness":128,"friendly_name":"Küche"}',
        'list.1.n': 'b',
        'list.2.n': null,
        'list.x': null,
        'state.x': null,
        'fehlt': null,
      };
      for (final MapEntry(key: path, value: expected) in cases.entries) {
        test(path, () async {
          final m = mockRunner((_) async => jsonResponse(answer));
          final r = await m.runner.call(def(responsePath: path), {'id': '1'});
          if (expected == null) {
            expect(r.isError, isTrue);
            expect(r.error, contains('nicht in der Antwort gefunden'));
          } else {
            expect(r.isError, isFalse);
            expect(r.text, expected);
          }
        });
      }

      test('kein JSON', () async {
        final m = mockRunner((_) async => http.Response('kein json', 200));
        final r = await m.runner.call(def(responsePath: 'a'), {'id': '1'});
        expect(r.error, contains('kein JSON'));
      });

      test('leere Antwort bleibt leer', () async {
        final m = mockRunner((_) async => http.Response('', 200));
        final r = await m.runner.call(def(responsePath: 'a'), {'id': '1'});
        expect(r.isError, isFalse);
        expect(r.text, '');
      });

      test('bei 4xx nicht angewendet', () async {
        final m = mockRunner((_) async => jsonResponse('{"a":1}', status: 404));
        final r = await m.runner.call(def(responsePath: 'a'), {'id': '1'});
        expect(r.status, 404);
        expect(r.text, '{"a":1}');
      });
    });
  });

  group('Weiterleitungen', () {
    http.Response redirect(String to, [int status = 302]) =>
        http.Response('', status, headers: {'location': to});

    test('gleicher Origin wird verfolgt, Secret bleibt', () async {
      var n = 0;
      final m = mockRunner(
        (_) async => n++ == 0 ? redirect('/neu?x=1') : jsonResponse('{}'),
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.isError, isFalse);
      expect(r.finalUrl.toString(), 'https://api.example.org/neu?x=1');
      expect(m.rec.requests.last.headers['Authorization'], 'Bearer $canary');
    });

    for (final to in [
      'https://other.example.org/x',
      'http://api.example.org/x',
      'https://api.example.org:8443/x',
      'https://evil.example/steal',
      '//evil.example/steal',
      'https://user@api.example.org/x',
    ]) {
      test('fremder Origin abgelehnt, nichts gesendet: $to', () async {
        final m = mockRunner((_) async => redirect(to));
        final r = await m.runner.call(def(), {'id': '1'});
        expect(r.isError, isTrue);
        expect(r.error, contains('Weiterleitung auf ein anderes Ziel'));
        expect(m.rec.requests, hasLength(1));
      });
    }

    test('höchstens 3 Weiterleitungen', () async {
      final m = mockRunner((_) async => redirect('/loop'));
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.error, contains('Zu viele Weiterleitungen'));
      expect(m.rec.requests, hasLength(4));
    });

    test('3 Weiterleitungen sind noch erlaubt', () async {
      var n = 0;
      final m = mockRunner(
        (_) async => n++ < 3 ? redirect('/r$n') : jsonResponse('{}'),
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.isError, isFalse);
      expect(m.rec.requests, hasLength(4));
    });

    test('303 wechselt auf GET ohne Body, 307 behält POST', () async {
      for (final (status, method, body) in [
        (303, 'GET', ''),
        (302, 'GET', ''),
        (307, 'POST', '{"a":"1"}'),
        (308, 'POST', '{"a":"1"}'),
      ]) {
        var n = 0;
        final m = mockRunner(
          (_) async =>
              n++ == 0 ? redirect('/weiter', status) : jsonResponse('{}'),
        );
        await m.runner.call(
          def(
            method: HttpMethod.post,
            url: 'https://api.example.org/x',
            body: {'a': '{id}'},
          ),
          {'id': '1'},
        );
        expect(m.rec.requests.last.method, method, reason: '$status');
        expect(m.rec.bodies.last, body, reason: '$status');
        if (body.isEmpty) {
          expect(
            m.rec.requests.last.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('content-type')),
          );
        }
      }
    });
  });

  group('Fehler vor dem Senden', () {
    test('DNS-Rebinding: nichts gesendet, kein Secret gelesen', () async {
      final m = mockRunner((_) async => jsonResponse('{}'));
      final r = await m.runner.call(
        def(url: 'https://rebind.example.org/x/{id}'),
        {'id': '1'},
      );
      expect(r.isError, isTrue);
      expect(r.error, contains('private Netz'));
      expect(m.rec.requests, isEmpty);
      expect(m.secrets.reads, isEmpty);
    });

    test(
      'fehlendes Pflichtargument: lesbarer Fehler, nichts gelesen',
      () async {
        final m = mockRunner((_) async => jsonResponse('{}'));
        final r = await m.runner.call(def(), {'q': 'x'});
        expect(r.error, 'Ungültige Argumente: „id“ fehlt');
        expect(r.request, isNull);
        expect(m.secrets.reads, isEmpty);
        expect(m.rec.requests, isEmpty);
      },
    );

    test('ungültige Definition', () async {
      final m = mockRunner((_) async => jsonResponse('{}'));
      final r = await m.runner.call(def(url: 'https://{host}/x'), {'id': '1'});
      expect(r.error, startsWith('Definition ungültig'));
    });

    test('Secret fehlt', () async {
      final m = mockRunner((_) async => jsonResponse('{}'), secrets: {});
      final r = await m.runner.call(def(), {'id': '1'});
      expect(
        r.error,
        contains('Zugangsdaten für Header „Authorization“ fehlen'),
      );
      expect(m.rec.requests, isEmpty);
    });

    test('Secret mit Zeilenumbruch wird nicht gesendet', () async {
      final m = mockRunner(
        (_) async => jsonResponse('{}'),
        secrets: {'tok': 'abc\r\nX-Evil: 1'},
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.error, contains('ungültig'));
      expect(r.error, isNot(contains('abc')));
      expect(m.rec.requests, isEmpty);
    });

    test('SecretStore wirft', () async {
      final m = mockRunner((_) async => jsonResponse('{}'));
      m.secrets.error = Exception(canary);
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.error, 'Zugangsdaten konnten nicht gelesen werden');
    });

    test('Server nicht erreichbar', () async {
      final m = mockRunner(
        (_) async => throw http.ClientException('x $canary'),
      );
      final r = await m.runner.call(def(), {'id': '1'});
      expect(r.error, 'Server „api.example.org“ nicht erreichbar');
    });

    test('Verbindungsabbruch während der Antwort', () async {
      final runner = HttpToolRunner(
        transport: ClientHttpToolTransport(
          MockClient.streaming(
            (request, body) async => http.StreamedResponse(
              Stream<List<int>>.error(const FormatException('weg')),
              200,
            ),
          ),
        ),
        secrets: FakeHttpToolSecrets({'tok': canary}),
        resolve: testDns,
      );
      final r = await runner.call(def(), {'id': '1'});
      expect(r.error, contains('abgebrochen'));
    });

    test('Abbruch über CancelToken', () async {
      final m = mockRunner((_) => Completer<http.Response>().future);
      final cancel = CancelToken();
      final f = m.runner.call(def(), {'id': '1'}, cancel: cancel);
      await Future<void>.delayed(Duration.zero);
      cancel.cancel();
      await expectLater(f, throwsA(isA<CancelledException>()));
      final pre = CancelToken()..cancel();
      await expectLater(
        m.runner.call(def(), {'id': '1'}, cancel: pre),
        throwsA(isA<CancelledException>()),
      );
    });
  });

  test('Secrets werden erst nach der Zielprüfung gelesen', () async {
    final order = <String>[];
    final secrets = FakeHttpToolSecrets({'tok': canary});
    final runner = HttpToolRunner(
      transport: ClientHttpToolTransport(
        MockClient((_) async {
          order.add('send');
          return jsonResponse('{}');
        }),
      ),
      secrets: secrets,
      resolve: (host) {
        order.add('dns:${secrets.reads.length}');
        return testDns(host);
      },
    );
    await runner.call(def(), {'id': '1'});
    expect(order, ['dns:0', 'send']);
    expect(secrets.reads, ['tok']);
  });
}
