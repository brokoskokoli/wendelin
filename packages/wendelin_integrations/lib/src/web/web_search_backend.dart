import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';

/// A web search service (Brave, Tavily, SearXNG). Must pass
/// `webSearchBackendContract`.
abstract interface class WebSearchBackend {
  /// Stable id, e.g. `brave`.
  String get id;

  /// Name for the UI and error messages.
  String get displayName;

  /// Up to [count] results for [query].
  ///
  /// Throws [ArgumentError] for a blank query or a [count] outside 1–20,
  /// `PortException(unavailable)` for unreachable services, invalid keys or
  /// rate limits, `PortException(failed)` for unreadable answers, and
  /// [CancelledException] when [cancel] fires first.
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  });
}

/// One search hit.
@immutable
final class WebSearchResult {
  /// Creates a result.
  const WebSearchResult({
    required this.title,
    required this.url,
    this.snippet = '',
  });

  /// Page title.
  final String title;

  /// Absolute http(s) URL.
  final String url;

  /// Short excerpt (plain text).
  final String snippet;

  /// JSON for the model.
  Map<String, Object?> toJson() => {
    'title': title,
    'url': url,
    if (snippet.isNotEmpty) 'snippet': snippet,
  };

  @override
  bool operator ==(Object other) =>
      other is WebSearchResult &&
      other.title == title &&
      other.url == url &&
      other.snippet == snippet;

  @override
  int get hashCode => Object.hash(title, url, snippet);

  @override
  String toString() => 'WebSearchResult($title, $url)';
}

/// Validates the common [WebSearchBackend.search] arguments.
void checkSearchArgs(String query, int count) {
  if (query.trim().isEmpty) {
    throw ArgumentError.value(query, 'query', 'darf nicht leer sein');
  }
  RangeError.checkValueInInterval(count, 1, 20, 'count');
}

/// Completes with [future] or throws [CancelledException] once [cancel]
/// fires, whichever comes first.
///
/// [future] is usually already running (e.g. `send(…).timeout(…)`). If
/// [cancel] has fired before, its result is dropped: a later error (such as
/// the [TimeoutException] of the abandoned request) must not surface as an
/// uncaught error.
Future<T> orCancel<T>(Future<T> future, CancelToken? cancel) {
  if (cancel == null) return future;
  if (cancel.isCancelled) {
    future.ignore();
    throw const CancelledException();
  }
  return Future.any([
    future,
    cancel.whenCancelled.then<T>((_) => throw const CancelledException()),
  ]);
}

/// Sends [request] with [client] and decodes a JSON answer, mapping
/// failures to [PortException]s that name [service] but never the key.
Future<Object?> sendForJson(
  http.Client client,
  http.BaseRequest request, {
  required String service,
  CancelToken? cancel,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final http.Response response;
  try {
    response = await orCancel(
      client.send(request).then(http.Response.fromStream).timeout(timeout),
      cancel,
    );
  } on TimeoutException {
    throw PortException(
      PortErrorKind.unavailable,
      '$service antwortet nicht (Zeitüberschreitung)',
    );
  } on http.ClientException {
    throw PortException(
      PortErrorKind.unavailable,
      '$service ist nicht erreichbar',
    );
  } on SocketException {
    throw PortException(
      PortErrorKind.unavailable,
      '$service ist nicht erreichbar',
    );
  }
  final status = response.statusCode;
  if (status == 401 || status == 403) {
    throw PortException(
      PortErrorKind.unavailable,
      '$service: API-Schlüssel fehlt oder ist ungültig',
    );
  }
  if (status == 429) {
    throw PortException(
      PortErrorKind.unavailable,
      '$service: Anfragelimit erreicht, später erneut versuchen',
    );
  }
  if (status < 200 || status >= 300) {
    throw PortException(
      PortErrorKind.unavailable,
      '$service antwortet mit Status $status',
    );
  }
  try {
    return jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
  } on FormatException {
    throw PortException(PortErrorKind.failed, '$service: unerwartete Antwort');
  }
}

/// Reads `json[key]` as a list of JSON objects (missing = empty), or throws
/// `PortException(failed)`.
List<Map<String, Object?>> readResultList(
  Object? json,
  List<String> path,
  String service,
) {
  Object? node = json;
  for (final key in path) {
    if (node is! Map<String, Object?>) {
      throw PortException(
        PortErrorKind.failed,
        '$service: unerwartete Antwort',
      );
    }
    node = node[key];
    if (node == null) return const [];
  }
  if (node is! List<Object?>) {
    throw PortException(PortErrorKind.failed, '$service: unerwartete Antwort');
  }
  return [
    for (final e in node)
      if (e is Map<String, Object?>) e,
  ];
}

final _tags = RegExp('<[^>]*>');

/// Builds a [WebSearchResult] from raw fields, skipping hits without title
/// or with a non-http(s) URL. HTML tags and entities in snippets are
/// removed.
WebSearchResult? resultFrom(Object? title, Object? url, Object? snippet) {
  if (title is! String || url is! String || title.trim().isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  String clean(String s) =>
      _unescape(s.replaceAll(_tags, '')).replaceAll(RegExp(r'\s+'), ' ').trim();
  return WebSearchResult(
    title: clean(title),
    url: url,
    snippet: snippet is String ? clean(snippet) : '',
  );
}

String _unescape(String s) => s
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

/// Brave Search API (`api.search.brave.com`, header
/// `X-Subscription-Token`).
final class BraveSearchBackend implements WebSearchBackend {
  /// Creates the backend; the key comes from the app's `SecretStore`.
  BraveSearchBackend({
    required this._apiKey,
    required this._client,
    Uri? endpoint,
  }) : endpoint =
           endpoint ??
           Uri.parse('https://api.search.brave.com/res/v1/web/search');

  final String _apiKey;
  final http.Client _client;

  /// Search endpoint.
  final Uri endpoint;

  @override
  String get id => 'brave';

  @override
  String get displayName => 'Brave Search';

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  }) async {
    checkSearchArgs(query, count);
    final request = http.Request(
      'GET',
      endpoint.replace(
        queryParameters: {
          'q': query,
          'count': '$count',
          'search_lang': ?language,
        },
      ),
    );
    request.headers.addAll({
      'Accept': 'application/json',
      'X-Subscription-Token': _apiKey,
    });
    final json = await sendForJson(
      _client,
      request,
      service: displayName,
      cancel: cancel,
    );
    return [
      for (final r in readResultList(json, const [
        'web',
        'results',
      ], displayName))
        ?resultFrom(r['title'], r['url'], r['description']),
    ].take(count).toList();
  }
}

/// Tavily search API (`api.tavily.com/search`, Bearer key).
final class TavilyBackend implements WebSearchBackend {
  /// Creates the backend; the key comes from the app's `SecretStore`.
  TavilyBackend({required this._apiKey, required this._client, Uri? endpoint})
    : endpoint = endpoint ?? Uri.parse('https://api.tavily.com/search');

  final String _apiKey;
  final http.Client _client;

  /// Search endpoint.
  final Uri endpoint;

  @override
  String get id => 'tavily';

  @override
  String get displayName => 'Tavily';

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  }) async {
    checkSearchArgs(query, count);
    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      })
      ..body = jsonEncode({
        'query': query,
        'max_results': count,
        'search_depth': 'basic',
      });
    final json = await sendForJson(
      _client,
      request,
      service: displayName,
      cancel: cancel,
    );
    return [
      for (final r in readResultList(json, const ['results'], displayName))
        ?resultFrom(r['title'], r['url'], r['content']),
    ].take(count).toList();
  }
}

/// Self-hosted SearXNG (`<base>/search?format=json`; JSON output must be
/// enabled in its `settings.yml`).
final class SearxngBackend implements WebSearchBackend {
  /// Creates the backend for the instance at [baseUrl], e.g.
  /// `https://search.example.org`.
  SearxngBackend({required this.baseUrl, required this._client});

  /// Instance root.
  final Uri baseUrl;

  final http.Client _client;

  @override
  String get id => 'searxng';

  @override
  String get displayName => 'SearXNG';

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  }) async {
    checkSearchArgs(query, count);
    final base = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    final request = http.Request(
      'GET',
      base
          .resolve('search')
          .replace(
            queryParameters: {
              'q': query,
              'format': 'json',
              'language': ?language,
            },
          ),
    )..headers['Accept'] = 'application/json';
    final json = await sendForJson(
      _client,
      request,
      service: displayName,
      cancel: cancel,
    );
    return [
      for (final r in readResultList(json, const ['results'], displayName))
        ?resultFrom(r['title'], r['url'], r['content']),
    ].take(count).toList();
  }
}
