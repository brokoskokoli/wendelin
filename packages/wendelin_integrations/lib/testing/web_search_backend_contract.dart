import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../src/common/port_exception.dart';
import '../src/web/web_search_backend.dart';

/// Situations a [WebSearchBackend] must handle in [webSearchBackendContract].
enum WebSearchScenario {
  /// The service answers the query `wendelin` with at least 3 hits.
  results,

  /// The service answers with no hits.
  empty,

  /// The service rejects the key (HTTP 401/403).
  unauthorized,

  /// The service reports a rate limit (HTTP 429).
  rateLimited,

  /// The service answers with something that is not the expected JSON.
  malformed,
}

/// API key the factories should configure; error messages must not
/// contain it.
const webSearchContractKey = 'test-key-wendelin';

/// Creates the backend under test for [scenario], e.g. with a mock HTTP
/// client serving a fixture, configured with [webSearchContractKey]. Return
/// `null` if a scenario cannot be set up (e.g. against the live service);
/// its check then passes without assertions.
typedef WebSearchBackendFactory = FutureOr<WebSearchBackend?> Function(
  WebSearchScenario scenario,
);

/// Names of the checks in [webSearchBackendContractChecks].
abstract final class WebSearchChecks {
  /// Hits: at most count, http(s) URLs, titles, no HTML.
  static const results =
      'Treffer: höchstens count, http(s)-URLs, Titel, Text ohne HTML';

  /// No hits: empty list.
  static const empty = 'keine Treffer: leere Liste';

  /// Invalid key: unavailable, key not in the message.
  static const unauthorized =
      'ungültiger Schlüssel: PortException(unavailable) ohne Schlüssel';

  /// Rate limit: unavailable.
  static const rateLimited = 'Anfragelimit: PortException(unavailable)';

  /// Unreadable answer: failed.
  static const malformed = 'unlesbare Antwort: PortException(failed)';

  /// Invalid arguments: ArgumentError.
  static const invalidArgs = 'ungültige Argumente: ArgumentError';

  /// Cancelled token: CancelledException.
  static const cancelled = 'abgebrochenes Token: CancelledException';
}

/// Reusable contract suite for every [WebSearchBackend] (Brave, Tavily,
/// SearXNG, fake); registers one test per entry of
/// [webSearchBackendContractChecks].
void webSearchBackendContract(
  WebSearchBackendFactory create, {
  String name = 'WebSearchBackend',
}) {
  group('$name erfüllt den WebSearchBackend-Vertrag', () {
    webSearchBackendContractChecks(create).forEach(test);
  });
}

/// The checks of [webSearchBackendContract] by name ([WebSearchChecks]).
Map<String, Future<void> Function()> webSearchBackendContractChecks(
  WebSearchBackendFactory create,
) {
  Future<void> inScenario(
    WebSearchScenario s,
    Future<void> Function(WebSearchBackend b) body,
  ) async {
    final b = await create(s);
    if (b != null) await body(b);
  }

  Future<void> failsWith(WebSearchScenario s, PortErrorKind kind) =>
      inScenario(s, (b) async {
        await expectLater(
          b.search('wendelin'),
          throwsA(
            isA<PortException>()
                .having((e) => e.kind, 'kind', kind)
                .having(
                  (e) => e.message,
                  'message',
                  isNot(contains(webSearchContractKey)),
                ),
          ),
        );
      });

  return {
    WebSearchChecks.results: () =>
        inScenario(WebSearchScenario.results, (b) async {
          expect(b.id, matches(RegExp(r'^[a-z0-9_]+$')));
          expect(b.displayName, isNotEmpty);
          final hits = await b.search('wendelin', count: 5);
          expect(hits.length, inInclusiveRange(3, 5));
          for (final h in hits) {
            expect(h.title.trim(), isNotEmpty);
            final uri = Uri.parse(h.url);
            expect(uri.isScheme('http') || uri.isScheme('https'), isTrue);
            expect(h.snippet, isNot(contains('<')));
            expect(h.title, isNot(contains('<')));
          }
          final two = await b.search('wendelin', count: 2);
          expect(two.length, inInclusiveRange(1, 2));
        }),
    WebSearchChecks.empty: () => inScenario(WebSearchScenario.empty, (b) async {
      expect(await b.search('wendelin'), isEmpty);
    }),
    WebSearchChecks.unauthorized: () =>
        failsWith(WebSearchScenario.unauthorized, PortErrorKind.unavailable),
    WebSearchChecks.rateLimited: () =>
        failsWith(WebSearchScenario.rateLimited, PortErrorKind.unavailable),
    WebSearchChecks.malformed: () =>
        failsWith(WebSearchScenario.malformed, PortErrorKind.failed),
    WebSearchChecks.invalidArgs: () =>
        inScenario(WebSearchScenario.results, (b) async {
          final invalid = throwsA(isA<ArgumentError>());
          await expectLater(b.search('  '), invalid);
          await expectLater(b.search('x', count: 0), invalid);
          await expectLater(b.search('x', count: 21), invalid);
        }),
    WebSearchChecks.cancelled: () =>
        inScenario(WebSearchScenario.results, (b) async {
          final token = CancelToken()..cancel();
          await expectLater(
            b.search('wendelin', cancel: token),
            throwsA(isA<CancelledException>()),
          );
        }),
  };
}
