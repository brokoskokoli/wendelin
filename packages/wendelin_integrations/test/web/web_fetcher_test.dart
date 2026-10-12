import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'fetch_guard_test.dart' show fakeDns;

String fixture(String name) =>
    File('test/fixtures/web/$name').readAsStringSync();

WebFetcher fetcher(
  Future<http.StreamedResponse> Function(http.BaseRequest r) handler, {
  int maxBytes = 2 * 1024 * 1024,
  Set<String> allowed = const {},
  Duration timeout = const Duration(seconds: 5),
}) => WebFetcher(
  client: MockClient.streaming((r, _) => handler(r)),
  resolve: fakeDns,
  maxBytes: maxBytes,
  allowedHosts: allowed,
  timeout: timeout,
);

http.StreamedResponse respond(
  Object body, {
  int status = 200,
  String? type = 'text/html; charset=utf-8',
  Map<String, String> headers = const {},
}) => http.StreamedResponse(
  Stream.value(body is String ? utf8.encode(body) : body as List<int>),
  status,
  headers: {'content-type': ?type, ...headers},
);

Matcher port(PortErrorKind kind, [String text = '']) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', contains(text)),
);

void main() {
  final page = Uri.parse('https://example.org/seite');

  test(
    'HTML wird zu lesbarem Text ohne Skripte, Stile und Navigation',
    () async {
      final f = fetcher((_) async => respond(fixture('page.html')));
      final p = await f.fetch(page);
      expect(p.title, 'Tauchbasis am Hafen');
      expect(p.contentType, 'text/html');
      expect(p.truncated, isFalse);
      expect(p.url, page);
      expect(p.text, contains('# Öffnungszeiten'));
      expect(p.text, contains('Wir haben täglich von 9 bis 18 Uhr geöffnet.'));
      expect(p.text, contains('- Schnuppertauchen\n- Nachttauchen'));
      expect(p.text, contains('| OWD | 399 €'));
      for (final hidden in [
        'secret',
        'color: red',
        'Kontakt',
        'Impressum',
        'JS aus',
        'versteckt',
      ]) {
        expect(p.text, isNot(contains(hidden)), reason: hidden);
      }
    },
  );

  test('Anfrage: GET ohne automatische Weiterleitung', () async {
    late http.BaseRequest seen;
    final f = fetcher((r) async {
      seen = r;
      return respond('ok', type: 'text/plain');
    });
    await f.fetch(page);
    expect(seen.method, 'GET');
    expect(seen.followRedirects, isFalse);
    expect(seen.headers['Accept'], contains('text/html'));
  });

  test('Weiterleitung wird verfolgt und relativ aufgelöst', () async {
    final urls = <Uri>[];
    final f = fetcher((r) async {
      urls.add(r.url);
      if (r.url.path == '/alt') {
        return respond('', status: 301, headers: {'location': '/neu'});
      }
      return respond('<title>Neu</title><p>Inhalt</p>');
    });
    final p = await f.fetch(Uri.parse('https://example.org/alt'));
    expect(urls.map((u) => u.toString()), [
      'https://example.org/alt',
      'https://example.org/neu',
    ]);
    expect(p.url.toString(), 'https://example.org/neu');
    expect(p.title, 'Neu');
  });

  test('Weiterleitung ins Heimnetz wird geblockt', () async {
    var calls = 0;
    final f = fetcher((r) async {
      calls++;
      return respond(
        '',
        status: 302,
        headers: {'location': 'http://192.168.178.1/admin'},
      );
    });
    await expectLater(
      f.fetch(page),
      port(PortErrorKind.rejected, 'privates Netz'),
    );
    expect(calls, 1);
  });

  test('zu viele Weiterleitungen', () async {
    var n = 0;
    final f = fetcher(
      (r) async => respond('', status: 302, headers: {'location': '/s${n++}'}),
    );
    await expectLater(f.fetch(page), port(PortErrorKind.failed, 'Zu viele'));
    expect(n, 6);
  });

  test('Weiterleitung ohne Ziel', () async {
    final f = fetcher((_) async => respond('', status: 302));
    await expectLater(f.fetch(page), port(PortErrorKind.failed, 'ohne Ziel'));
  });

  test('geblocktes Ziel: kein Request', () async {
    var calls = 0;
    final f = fetcher((_) async {
      calls++;
      return respond('x');
    });
    for (final url in [
      'file:///etc/passwd',
      'http://localhost/',
      'http://10.1.2.3/',
      'http://192.168.0.10/',
    ]) {
      await expectLater(f.fetch(Uri.parse(url)), port(PortErrorKind.rejected));
    }
    expect(calls, 0);
  });

  test('Allowlist erlaubt den Homeserver', () async {
    final f = fetcher(
      (_) async => respond('ok', type: 'text/plain'),
      allowed: {'192.168.0.10'},
    );
    expect((await f.fetch(Uri.parse('http://192.168.0.10/status'))).text, 'ok');
  });

  test('Statusfehler', () async {
    await expectLater(
      fetcher((_) async => respond('weg', status: 404)).fetch(page),
      port(PortErrorKind.notFound, 'Status 404'),
    );
    await expectLater(
      fetcher((_) async => respond('kaputt', status: 503)).fetch(page),
      port(PortErrorKind.unavailable, 'Status 503'),
    );
  });

  test('Netzwerkfehler und Zeitüberschreitung', () async {
    await expectLater(
      fetcher((_) async => throw http.ClientException('weg')).fetch(page),
      port(PortErrorKind.unavailable, 'nicht erreichbar'),
    );
    await expectLater(
      fetcher((_) async => throw const SocketException('weg')).fetch(page),
      port(PortErrorKind.unavailable, 'nicht erreichbar'),
    );
    await expectLater(
      fetcher(
        (_) => Completer<http.StreamedResponse>().future,
        timeout: const Duration(milliseconds: 10),
      ).fetch(page),
      port(PortErrorKind.unavailable, 'Zeitüberschreitung'),
    );
  });

  test('Körper hängt: Zeitüberschreitung', () async {
    final f = fetcher(
      (_) async => http.StreamedResponse(
        StreamController<List<int>>().stream,
        200,
        headers: {'content-type': 'text/plain'},
      ),
      timeout: const Duration(milliseconds: 10),
    );
    await expectLater(
      f.fetch(page),
      port(PortErrorKind.unavailable, 'Zeitüberschreitung'),
    );
  });

  test('Verbindung bricht beim Lesen ab', () async {
    final f = fetcher(
      (_) async => http.StreamedResponse(
        Stream<List<int>>.error(const SocketException('reset')),
        200,
        headers: {'content-type': 'text/plain'},
      ),
    );
    await expectLater(
      f.fetch(page),
      port(PortErrorKind.unavailable, 'abgebrochen'),
    );
  });

  test('nicht unterstützte Inhaltstypen', () async {
    for (final type in [
      'application/pdf',
      'image/png',
      'application/octet-stream',
    ]) {
      await expectLater(
        fetcher((_) async => respond([1, 2, 3], type: type)).fetch(page),
        port(PortErrorKind.unsupported, type),
      );
    }
  });

  test('Text, JSON und XML werden unverändert geliefert', () async {
    for (final type in [
      'text/plain',
      'application/json',
      'application/ld+json',
      'text/csv',
      'application/xml',
    ]) {
      final p = await fetcher((_) async => respond('a <b> c', type: type))
          .fetch(page);
      expect(p.text, 'a <b> c', reason: type);
      expect(p.contentType, type);
      expect(p.title, isNull);
    }
  });

  test('ohne Content-Type: HTML wird erkannt, sonst Text', () async {
    final html = await fetcher((_) async => respond('<p>Hallo</p>', type: null))
        .fetch(page);
    expect(html.text, 'Hallo');
    expect(html.contentType, 'text/html');
    final text = await fetcher((_) async => respond('Hallo <Welt>', type: null))
        .fetch(page);
    expect(text.text, 'Hallo <Welt>');
    expect(text.contentType, 'text/plain');
  });

  test('Zeichensatz latin1', () async {
    final p = await fetcher(
      (_) async => respond(
        latin1.encode('Grüße'),
        type: 'text/plain; charset="ISO-8859-1"',
      ),
    ).fetch(page);
    expect(p.text, 'Grüße');
  });

  test(
    'Größenlimit: liest höchstens maxBytes und markiert die Kürzung',
    () async {
      var delivered = 0;
      final controller = StreamController<List<int>>();
      final f = fetcher((_) async {
        for (var i = 0; i < 10; i++) {
          controller.add(utf8.encode('x' * 100));
          delivered += 100;
        }
        unawaited(controller.close());
        return http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/plain'},
        );
      }, maxBytes: 250);
      final p = await f.fetch(page);
      expect(p.text, 'x' * 250);
      expect(p.truncated, isTrue);
      expect(delivered, 1000);
    },
  );

  test('genau maxBytes ist nicht gekürzt', () async {
    final p = await fetcher(
      (_) async => respond('y' * 100, type: 'text/plain'),
      maxBytes: 100,
    ).fetch(page);
    expect(p.text, hasLength(100));
    expect(p.truncated, isFalse);
  });

  test('Standardlimit ist 2 MB', () {
    expect(
      WebFetcher(client: MockClient((_) async => http.Response('', 200)))
          .maxBytes,
      2 * 1024 * 1024,
    );
  });

  test('Abbruch', () async {
    final token = CancelToken();
    final f = fetcher((_) => Completer<http.StreamedResponse>().future);
    final future = f.fetch(page, cancel: token);
    token.cancel();
    await expectLater(future, throwsA(isA<CancelledException>()));
    await expectLater(
      f.fetch(page, cancel: token),
      throwsA(isA<CancelledException>()),
    );
  });
}
