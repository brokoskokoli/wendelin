import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart' show ellipsize;
import '../common/net_scope.dart' show HostResolver;
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import '../web/web_search_backend.dart' show orCancel;
import 'http_target.dart';
import 'http_template.dart';
import 'http_tool_definition.dart';
import 'http_transport.dart';

/// Placeholder shown instead of secret header values.
const redactedSecret = '••••••';

/// Placeholder replacing secrets a server echoes back.
const scrubbedSecret = '[geheim]';

/// The request as it was (or would be) sent, without secrets: secret
/// header values are [redactedSecret]. For the editor preview and logs.
@immutable
final class SentRequest {
  /// Creates the description.
  SentRequest({
    required this.method,
    required this.url,
    required Map<String, String> headers,
    this.body,
  }) : headers = Map.unmodifiable(headers);

  /// Longest body kept in [body].
  static const maxBodyChars = 2000;

  /// HTTP method.
  final String method;

  /// URL of the first request (no secrets: secrets only go into headers).
  final Uri url;

  /// Headers; secret values replaced by [redactedSecret].
  final Map<String, String> headers;

  /// Body text (shortened to [maxBodyChars]), if any.
  final String? body;

  /// JSON for the editor preview.
  Map<String, Object?> toJson() => {
    'method': method,
    'url': url.toString(),
    'headers': headers,
    if (body != null) 'body': body,
  };

  @override
  String toString() => 'SentRequest($method $url)';
}

/// Outcome of [HttpToolRunner.call]. Never contains secrets.
@immutable
final class HttpCallResult {
  /// Creates a result.
  const HttpCallResult({
    required this.duration,
    this.request,
    this.finalUrl,
    this.status,
    this.reason,
    this.contentType,
    this.text = '',
    this.truncated = false,
    this.error,
  });

  /// What was sent (`null` if the call failed before a request was built).
  final SentRequest? request;

  /// URL of the last request (after same-origin redirects).
  final Uri? finalUrl;

  /// HTTP status, if a response arrived.
  final int? status;

  /// Reason phrase of [status], if any.
  final String? reason;

  /// MIME type of the response without parameters.
  final String? contentType;

  /// Response text (after `responsePath`), secrets scrubbed.
  final String text;

  /// Whether the body exceeded the size limit and was cut.
  final bool truncated;

  /// Time from start to finish.
  final Duration duration;

  /// German, model-safe description of a failure without usable answer.
  final String? error;

  /// Whether the call failed ([error] or HTTP status ≥ 400).
  bool get isError => error != null || (status ?? 0) >= 400;

  @override
  String toString() =>
      'HttpCallResult(status: $status, error: $error, '
      'truncated: $truncated)';
}

final class _Prepared {
  _Prepared(this.url, this.headers, this.body, this.sent);

  final Uri url;
  final Map<String, String> headers;
  final String? body;
  final SentRequest sent;
}

final class _CallFailure implements Exception {
  _CallFailure(this.message, {this.status});

  final String message;
  final int? status;
}

/// Executes [HttpToolDefinition]s: fills the templates, checks the target
/// (`checkHttpTarget`, pinned addresses), reads secrets only right before
/// sending, follows at most [maxRedirects] same-origin redirects, enforces
/// the definition's timeout, reads at most [maxResponseBytes] of text/JSON
/// and applies `responsePath`.
///
/// Expected failures come back as [HttpCallResult.error]; only cancellation
/// throws ([CancelledException]).
final class HttpToolRunner {
  /// Creates a runner. [resolve] defaults to [InternetAddress.lookup];
  /// [allowLoopback] is the test mode (loopback/link-local targets).
  HttpToolRunner({
    required this.transport,
    required this.secrets,
    HostResolver? resolve,
    this.clock = const SystemClock(),
    this.maxResponseBytes = 256 * 1024,
    this.maxRedirects = 3,
    this.allowLoopback = false,
  }) : _resolve = resolve ?? InternetAddress.lookup;

  /// Sends the requests.
  final HttpToolTransport transport;

  /// Source of the secrets referenced by the auth methods.
  final HttpToolSecrets secrets;

  /// Time source for [HttpCallResult.duration].
  final Clock clock;

  /// Size limit of a response body (default 256 KB).
  final int maxResponseBytes;

  /// Most redirects followed (same origin only).
  final int maxRedirects;

  /// Test mode: loopback and link-local targets allowed.
  final bool allowLoopback;

  final HostResolver _resolve;

  /// Calls [definition] with [args]. Only cancellation throws; any other
  /// failure (also unexpected ones) comes back as [HttpCallResult.error].
  Future<HttpCallResult> call(
    HttpToolDefinition definition,
    Map<String, Object?> args, {
    CancelToken? cancel,
  }) async {
    final started = clock.now();
    // Beendet die Verbindung nach Ende, Zeitlimit oder Abbruch hart.
    final abort = CancelToken();
    try {
      return await _call(definition, args, cancel, started, abort);
    } on CancelledException {
      rethrow;
    } on Object catch (e, stack) {
      // Programmierfehler nicht verstecken: der Zone melden (die App
      // zeigt sie im Fehlerbericht), dem Modell aber nur einen festen Text.
      if (e is Error) Zone.current.handleUncaughtError(e, stack);
      // Letzte Linie: nie Ausnahme-Text (evtl. Server-Inhalt) weitergeben.
      return HttpCallResult(
        duration: clock.now().difference(started),
        error: 'Unerwarteter Fehler beim HTTP-Aufruf',
      );
    } finally {
      abort.cancel();
    }
  }

  Future<HttpCallResult> _call(
    HttpToolDefinition definition,
    Map<String, Object?> args,
    CancelToken? cancel,
    DateTime started,
    CancelToken abort,
  ) async {
    HttpCallResult fail(String message, [SentRequest? sent]) => HttpCallResult(
      duration: clock.now().difference(started),
      request: sent,
      error: message,
    );
    try {
      definition.validate();
    } on FormatException catch (e) {
      return fail('Definition ungültig: ${e.message}');
    }
    final _Prepared prepared;
    try {
      prepared = _prepare(definition, args);
    } on InvalidArgumentsException catch (e) {
      return fail('Ungültige Argumente: ${e.message}');
    }
    final used = <String>[];
    try {
      cancel?.throwIfCancelled();
      return await orCancel(
        _send(
          definition,
          prepared,
          used,
          started,
          abort,
        ).timeout(definition.timeout),
        cancel,
      );
    } on TimeoutException {
      return fail(
        'Zeitüberschreitung: keine Antwort nach '
        '${definition.timeout.inSeconds} s',
        prepared.sent,
      );
    } on PortException catch (e) {
      return fail(_scrub(e.message, used), prepared.sent);
    } on _CallFailure catch (e) {
      return HttpCallResult(
        duration: clock.now().difference(started),
        request: prepared.sent,
        status: e.status,
        error: _scrub(e.message, used),
      );
    }
  }

  _Prepared _prepare(HttpToolDefinition d, Map<String, Object?> args) {
    final required = d.inputSchema['required'];
    if (required is List<Object?>) {
      for (final r in required.whereType<String>()) {
        if (args[r] == null) throw InvalidArgumentsException('„$r“ fehlt');
      }
    }
    final url = d.url.expand(args);
    final headers = <String, String>{
      'Accept': 'application/json, text/*;q=0.9, */*;q=0.1',
      'User-Agent': 'Wendelin-HTTP-Tool',
    };
    String? body;
    final template = d.bodyTemplate;
    if (template != null) {
      switch (d.bodyFormat) {
        case HttpBodyFormat.json:
          body = jsonEncode(expandJsonBody(template, args));
          headers['Content-Type'] = 'application/json; charset=utf-8';
        case HttpBodyFormat.form:
          body = expandFormBody(template as Map<String, Object?>, args);
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
      }
    }
    _putAll(headers, expandHeaders(d.headers, args));
    final shown = {
      ...headers,
      for (final h in _secretHeaderNames(d.auth)) h: redactedSecret,
    };
    final sentBody = body == null || body.length <= SentRequest.maxBodyChars
        ? body
        : '${body.substring(0, SentRequest.maxBodyChars)}…';
    return _Prepared(
      url,
      headers,
      body,
      SentRequest(
        method: d.method.verb,
        url: url,
        headers: shown,
        body: sentBody,
      ),
    );
  }

  Future<HttpCallResult> _send(
    HttpToolDefinition d,
    _Prepared p,
    List<String> used,
    DateTime started,
    CancelToken abort,
  ) async {
    final target = await checkHttpTarget(
      p.url,
      homeNetwork: d.homeNetwork,
      resolve: _resolve,
      allowLoopback: allowLoopback,
    );
    // Secrets erst jetzt, unmittelbar vor dem Senden.
    final secretHeaders = await _readSecrets(d.auth, used);
    var url = p.url;
    var method = d.method.verb;
    var body = p.body;
    for (var hop = 0; ; hop++) {
      final request = http.Request(method, url)..followRedirects = false;
      _putAll(request.headers, p.headers);
      if (body == null) {
        request.headers.removeWhere(
          (k, _) => k.toLowerCase() == 'content-type',
        );
      } else {
        request.bodyBytes = utf8.encode(body);
      }
      _putAll(request.headers, secretHeaders);
      final http.StreamedResponse response;
      try {
        response = await transport.send(request, target, abort: abort);
      } on Exception {
        throw PortException(
          PortErrorKind.unavailable,
          'Server „${url.host}“ nicht erreichbar',
        );
      }
      final status = response.statusCode;
      final location = response.headers['location'];
      if (const {301, 302, 303, 307, 308}.contains(status) &&
          location != null) {
        await _discard(response);
        if (hop >= maxRedirects) {
          throw _CallFailure(
            'Zu viele Weiterleitungen (höchstens $maxRedirects)',
            status: status,
          );
        }
        final Uri next;
        try {
          next = url.resolve(location);
        } on FormatException {
          throw _CallFailure('Ungültige Weiterleitung', status: status);
        }
        if (!target.sameOrigin(next)) {
          throw _CallFailure(
            'Weiterleitung auf ein anderes Ziel '
            '(„${next.host.isEmpty ? next.scheme : next.host}“) abgelehnt',
            status: status,
          );
        }
        if (status == 303 ||
            ((status == 301 || status == 302) &&
                method != 'GET' &&
                method != 'HEAD')) {
          method = 'GET';
          body = null;
        }
        url = next;
        continue;
      }
      return _read(d, p, url, response, used, started);
    }
  }

  Future<HttpCallResult> _read(
    HttpToolDefinition d,
    _Prepared p,
    Uri url,
    http.StreamedResponse response,
    List<String> used,
    DateTime started,
  ) async {
    final status = response.statusCode;
    final contentType = response.headers['content-type'] ?? '';
    final mime = contentType.split(';').first.trim().toLowerCase();
    HttpCallResult result(
      String text, {
      bool truncated = false,
      String? error,
    }) => HttpCallResult(
      duration: clock.now().difference(started),
      request: p.sent,
      finalUrl: url,
      status: status,
      reason: response.reasonPhrase == null
          ? null
          : _scrub(response.reasonPhrase!, used),
      contentType: mime.isEmpty ? null : _scrub(mime, used),
      text: _scrub(text, used),
      truncated: truncated,
      error: error == null ? null : _scrub(error, used),
    );
    if (!_isText(mime)) {
      await _discard(response);
      final message =
          'Antwort vom Typ „$mime“ wird nicht unterstützt (nur Text und JSON)';
      return result('', error: status >= 400 ? null : message);
    }
    final body = await _readLimited(response.stream);
    final text = _decode(body.bytes, contentType);
    if (status >= 400) return result(text, truncated: body.truncated);
    final path = d.responsePath;
    if (path == null || text.isEmpty) {
      return result(text, truncated: body.truncated);
    }
    if (body.truncated) {
      return result(
        text,
        truncated: true,
        error:
            'Antwort größer als ${maxResponseBytes ~/ 1024} KB, '
            '„$path“ konnte nicht ausgewertet werden',
      );
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return result(
        text,
        error: 'Antwort ist kein JSON, „$path“ nicht anwendbar',
      );
    }
    final selected = selectJsonPath(json, path);
    if (!selected.found) {
      return result(text, error: '„$path“ nicht in der Antwort gefunden');
    }
    final value = selected.value;
    return result(value is String ? value : jsonEncode(value));
  }

  Future<Map<String, String>> _readSecrets(
    AuthMethod auth,
    List<String> used,
  ) async {
    final refs = switch (auth) {
      ApiKeyAuth(:final secretRef, :final headerName) => {
        headerName ?? 'Authorization': secretRef,
      },
      CustomHeadersAuth(:final secretRefsByHeader) => secretRefsByHeader,
      _ => const <String, String>{},
    };
    final out = <String, String>{};
    for (final e in refs.entries) {
      final String? value;
      try {
        value = await secrets.read(e.value);
      } on Exception {
        throw const PortException(
          PortErrorKind.unavailable,
          'Zugangsdaten konnten nicht gelesen werden',
        );
      }
      if (value == null || value.isEmpty) {
        throw PortException(
          PortErrorKind.rejected,
          'Zugangsdaten für Header „${e.key}“ fehlen – bitte in den '
          'Einstellungen hinterlegen',
        );
      }
      if (hasHeaderControlChars(value)) {
        throw PortException(
          PortErrorKind.rejected,
          'Gespeichertes Secret für Header „${e.key}“ ist ungültig '
          '(Zeilenumbruch)',
        );
      }
      used.add(value);
      final bearer = auth is ApiKeyAuth && auth.headerName == null;
      out[e.key] = bearer ? 'Bearer $value' : value;
    }
    return out;
  }

  Future<({List<int> bytes, bool truncated})> _readLimited(
    Stream<List<int>> stream,
  ) async {
    final bytes = <int>[];
    final done = Completer<bool>();
    late final StreamSubscription<List<int>> sub;
    sub = stream.listen(
      (chunk) {
        final room = maxResponseBytes - bytes.length;
        if (chunk.length > room) {
          bytes.addAll(chunk.take(room));
          unawaited(sub.cancel());
          if (!done.isCompleted) done.complete(true);
        } else {
          bytes.addAll(chunk);
        }
      },
      onError: (Object _) {
        if (!done.isCompleted) {
          done.completeError(
            const PortException(
              PortErrorKind.unavailable,
              'Verbindung während der Antwort abgebrochen',
            ),
          );
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete(false);
      },
      cancelOnError: true,
    );
    final truncated = await done.future;
    return (bytes: bytes, truncated: truncated);
  }
}

Set<String> _secretHeaderNames(AuthMethod auth) => switch (auth) {
  ApiKeyAuth(:final headerName) => {headerName ?? 'Authorization'},
  CustomHeadersAuth(:final secretRefsByHeader) =>
    secretRefsByHeader.keys.toSet(),
  _ => const {},
};

/// Sets [add] into [headers], replacing entries that differ only in case.
void _putAll(Map<String, String> headers, Map<String, String> add) {
  for (final e in add.entries) {
    headers
      ..removeWhere((k, _) => k.toLowerCase() == e.key.toLowerCase())
      ..[e.key] = e.value;
  }
}

Future<void> _discard(http.StreamedResponse response) async {
  try {
    await response.stream.listen(null).cancel();
  } on Object {
    // Rest der Antwort ist egal.
  }
}

bool _isText(String mime) =>
    mime.isEmpty ||
    mime.startsWith('text/') ||
    mime == 'application/json' ||
    mime == 'application/xml' ||
    mime == 'application/x-www-form-urlencoded' ||
    mime.endsWith('+json') ||
    mime.endsWith('+xml');

String _decode(List<int> bytes, String contentType) {
  final charset = RegExp(
    r'charset=([^;\s]+)',
    caseSensitive: false,
  ).firstMatch(contentType)?[1]?.toLowerCase().replaceAll('"', '');
  return switch (charset) {
    'iso-8859-1' ||
    'latin1' ||
    'windows-1252' ||
    'us-ascii' => latin1.decode(bytes),
    _ => utf8.decode(bytes, allowMalformed: true),
  };
}

/// [text] with every secret of [secrets] (also JSON-escaped and
/// URL-encoded) replaced by [scrubbedSecret].
String _scrub(String text, List<String> secrets) {
  var out = text;
  for (final s in secrets) {
    if (s.length < 4) continue;
    final escaped = jsonEncode(s);
    for (final form in {
      s,
      escaped.substring(1, escaped.length - 1),
      Uri.encodeComponent(s),
      Uri.encodeQueryComponent(s),
    }) {
      out = out.replaceAll(form, scrubbedSecret);
    }
  }
  return out;
}

/// Result of [selectJsonPath].
typedef JsonPathMatch = ({bool found, Object? value});

/// The value at the dot [path] in [json] (`data.items.0.name`; numeric
/// segments index lists).
JsonPathMatch selectJsonPath(Object? json, String path) {
  var current = json;
  for (final segment in path.split('.')) {
    if (current is Map<String, Object?> && current.containsKey(segment)) {
      current = current[segment];
    } else if (current is List<Object?>) {
      final i = int.tryParse(segment);
      if (i == null || i < 0 || i >= current.length) {
        return (found: false, value: null);
      }
      current = current[i];
    } else {
      return (found: false, value: null);
    }
  }
  return (found: true, value: current);
}

/// German one-line description of a call for the confirmation card:
/// method, host, path and query with the values inserted, and the
/// shortened body – never secrets (they are not even read).
String describeHttpCall(HttpToolDefinition d, Map<String, Object?> args) {
  final url = d.url.expand(args);
  final port = url.hasPort ? ':${url.port}' : '';
  final target =
      '${url.host}$port${url.path.isEmpty ? '/' : url.path}'
      '${url.hasQuery ? '?${url.query}' : ''}';
  final template = d.bodyTemplate;
  String? body;
  if (template != null) {
    body = switch (d.bodyFormat) {
      HttpBodyFormat.json => jsonEncode(expandJsonBody(template, args)),
      HttpBodyFormat.form => expandFormBody(
        template as Map<String, Object?>,
        args,
      ),
    };
  }
  return '${d.method.verb} ${ellipsize(target, 160)}'
      '${body == null ? '' : ' · Body: ${ellipsize(body, 120)}'}';
}
