import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/src/web/web_search_backend.dart'
    show sendForJson;
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

String fixture(String name) =>
    File('test/fixtures/web/$name').readAsStringSync();

/// Mock client answering every request with [body]/[status] and recording
/// the requests.
MockClient mock(List<http.Request> seen, String body, {int status = 200}) =>
    MockClient((request) async {
      seen.add(request);
      return http.Response.bytes(
        utf8.encode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

typedef _Make = WebSearchBackend Function(http.Client client);

void main() {
  final backends = <String, (_Make, Map<WebSearchScenario, (String, int)>)>{
    'BraveSearchBackend': (
      (c) => BraveSearchBackend(apiKey: webSearchContractKey, client: c),
      {
        WebSearchScenario.results: (fixture('brave_results.json'), 200),
        WebSearchScenario.empty: (fixture('brave_empty.json'), 200),
        WebSearchScenario.unauthorized: (
          fixture('brave_unauthorized.json'),
          401,
        ),
        WebSearchScenario.rateLimited: (
          fixture('brave_rate_limited.json'),
          429,
        ),
        WebSearchScenario.malformed: ('<html>Wartung</html>', 200),
      },
    ),
    'TavilyBackend': (
      (c) => TavilyBackend(apiKey: webSearchContractKey, client: c),
      {
        WebSearchScenario.results: (fixture('tavily_results.json'), 200),
        WebSearchScenario.empty: (fixture('tavily_empty.json'), 200),
        WebSearchScenario.unauthorized: (
          fixture('tavily_unauthorized.json'),
          401,
        ),
        WebSearchScenario.rateLimited: (
          '{"detail":{"error":"rate limit"}}',
          429,
        ),
        WebSearchScenario.malformed: ('{"results": "kaputt"}', 200),
      },
    ),
    'SearxngBackend': (
      (c) => SearxngBackend(
        baseUrl: Uri.parse('https://suche.example.org'),
        client: c,
      ),
      {
        WebSearchScenario.results: (fixture('searxng_results.json'), 200),
        WebSearchScenario.empty: (fixture('searxng_empty.json'), 200),
        WebSearchScenario.unauthorized: ('Forbidden', 403),
        WebSearchScenario.rateLimited: ('Too Many Requests', 429),
        WebSearchScenario.malformed: ('[1, 2, 3]', 200),
      },
    ),
  };

  backends.forEach((name, spec) {
    webSearchBackendContract((scenario) {
      final (body, status) = spec.$2[scenario]!;
      return spec.$1(mock([], body, status: status));
    }, name: name);
  });

  group('BraveSearchBackend', () {
    test('Anfrage: GET mit q, count, search_lang und Token-Header', () async {
      final seen = <http.Request>[];
      final b = BraveSearchBackend(
        apiKey: 'k1',
        client: mock(seen, fixture('brave_results.json')),
      );
      await b.search('tauchen hamburg', count: 3, language: 'de');
      final r = seen.single;
      expect(r.method, 'GET');
      expect(r.url.host, 'api.search.brave.com');
      expect(r.url.path, '/res/v1/web/search');
      expect(r.url.queryParameters, {
        'q': 'tauchen hamburg',
        'count': '3',
        'search_lang': 'de',
      });
      expect(r.headers['X-Subscription-Token'], 'k1');
    });

    test(
      'Antwort: HTML und Entitäten entfernt, ftp-Treffer verworfen',
      () async {
        final b = BraveSearchBackend(
          apiKey: 'k',
          client: mock([], fixture('brave_results.json')),
        );
        final hits = await b.search('wendelin', count: 10);
        expect(hits.map((h) => h.url), [
          'https://de.wikipedia.org/wiki/Wendelin',
          'https://www.sankt-wendel.de/',
          'https://example.org/wiedeking',
          'http://example.com/basilika',
        ]);
        expect(hits.first.title, 'Wendelin – Wikipedia');
        expect(
          hits.first.snippet,
          'Wendelin ist ein männlicher Vorname & Heiliger.',
        );
        expect(hits[2].snippet, 'Manager "Porsche"');
        expect(hits.last.toJson(), {
          'title': 'Wendelinusbasilika',
          'url': 'http://example.com/basilika',
        });
      },
    );

    test('count begrenzt die Treffer', () async {
      final b = BraveSearchBackend(
        apiKey: 'k',
        client: mock([], fixture('brave_results.json')),
      );
      expect(await b.search('wendelin', count: 1), hasLength(1));
    });
  });

  group('TavilyBackend', () {
    test('Anfrage: POST mit JSON-Body und Bearer-Header', () async {
      final seen = <http.Request>[];
      final b = TavilyBackend(
        apiKey: 'k2',
        client: mock(seen, fixture('tavily_results.json')),
      );
      final hits = await b.search('wendelin', count: 4);
      final r = seen.single;
      expect(r.method, 'POST');
      expect(r.url.toString(), 'https://api.tavily.com/search');
      expect(r.headers['Authorization'], 'Bearer k2');
      expect(jsonDecode(r.body), {
        'query': 'wendelin',
        'max_results': 4,
        'search_depth': 'basic',
      });
      expect(hits, hasLength(3), reason: 'Treffer ohne Titel verworfen');
      expect(hits.first.snippet, 'Wendelin ist ein männlicher Vorname.');
    });
  });

  group('SearxngBackend', () {
    test('Anfrage: <base>/search?format=json, auch mit Unterpfad', () async {
      for (final base in [
        'https://h.example/searx',
        'https://h.example/searx/',
      ]) {
        final seen = <http.Request>[];
        final b = SearxngBackend(
          baseUrl: Uri.parse(base),
          client: mock(seen, fixture('searxng_results.json')),
        );
        expect(b.id, 'searxng');
        await b.search('wendelin', language: 'de');
        expect(seen.single.url.path, '/searx/search');
        expect(seen.single.url.queryParameters, {
          'q': 'wendelin',
          'format': 'json',
          'language': 'de',
        });
      }
    });

    test(
      'Antwort: count schneidet, fehlender Inhalt ist leerer Snippet',
      () async {
        final b = SearxngBackend(
          baseUrl: Uri.parse('https://h.example'),
          client: mock([], fixture('searxng_results.json')),
        );
        final hits = await b.search('wendelin', count: 5);
        expect(hits, hasLength(5));
        expect(hits[2].snippet, isEmpty);
      },
    );
  });

  group('sendForJson', () {
    Future<Object?> send(
      http.Client c, {
      CancelToken? cancel,
      Duration? timeout,
    }) => sendForJson(
      c,
      http.Request('GET', Uri.parse('https://x.example')),
      service: 'Dienst',
      cancel: cancel,
      timeout: timeout ?? const Duration(seconds: 15),
    );

    Matcher port(PortErrorKind kind, String text) => throwsA(
      isA<PortException>()
          .having((e) => e.kind, 'kind', kind)
          .having((e) => e.message, 'message', contains(text)),
    );

    test('401 und 403 nennen den Schlüssel, 429 das Limit', () async {
      for (final status in [401, 403]) {
        await expectLater(
          send(mock([], 'x', status: status)),
          port(PortErrorKind.unavailable, 'API-Schlüssel'),
        );
      }
      await expectLater(
        send(mock([], 'x', status: 429)),
        port(PortErrorKind.unavailable, 'Anfragelimit'),
      );
    });

    test('Serverfehler 500', () async {
      await expectLater(
        send(mock([], 'x', status: 500)),
        port(PortErrorKind.unavailable, 'Status 500'),
      );
    });

    test('Netzwerkfehler', () async {
      await expectLater(
        send(MockClient((_) async => throw http.ClientException('weg'))),
        port(PortErrorKind.unavailable, 'nicht erreichbar'),
      );
      await expectLater(
        send(MockClient((_) async => throw const SocketException('weg'))),
        port(PortErrorKind.unavailable, 'nicht erreichbar'),
      );
    });

    test('Zeitüberschreitung', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        send(never, timeout: const Duration(milliseconds: 10)),
        port(PortErrorKind.unavailable, 'Zeitüberschreitung'),
      );
    });

    test('Abbruch während der Anfrage', () async {
      final never = MockClient((_) => Completer<http.Response>().future);
      final token = CancelToken();
      final f = send(never, cancel: token);
      token.cancel();
      await expectLater(f, throwsA(isA<CancelledException>()));
    });

    test('Abbruch vorab: verlassene Anfrage meldet später nichts', () {
      // Die Anfrage samt Zeitlimit läuft schon, wenn der abgebrochene Token
      // geprüft wird. Ihre spätere TimeoutException darf nicht unbehandelt
      // bleiben (sonst „failed after completed“ unter Last).
      fakeAsync((async) {
        final never = MockClient((_) => Completer<http.Response>().future);
        final token = CancelToken()..cancel();
        final result = <Object?>[];
        unawaited(
          send(
            never,
            cancel: token,
            timeout: const Duration(seconds: 1),
          ).then(result.add, onError: result.add),
        );
        async.flushMicrotasks();
        expect(result, [isA<CancelledException>()]);
        async.elapse(const Duration(seconds: 2));
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('readResultList: falsche Struktur', () async {
      final b = BraveSearchBackend(
        apiKey: 'k',
        client: mock([], '{"web": []}'),
      );
      await expectLater(
        b.search('x'),
        port(PortErrorKind.failed, 'unerwartete Antwort'),
      );
    });
  });

  test('WebSearchResult: Gleichheit', () {
    const a = WebSearchResult(title: 't', url: 'https://a', snippet: 's');
    expect(
      a,
      const WebSearchResult(title: 't', url: 'https://a', snippet: 's'),
    );
    expect(
      a.hashCode,
      const WebSearchResult(
        title: 't',
        url: 'https://a',
        snippet: 's',
      ).hashCode,
    );
    expect(
      a,
      isNot(const WebSearchResult(title: 't', url: 'https://b', snippet: 's')),
    );
    expect(a.toString(), contains('https://a'));
  });
}
