import 'dart:async';
import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../errors.dart';
import '../net_policy.dart';

/// Time and size limits of MCP exchanges.
@immutable
final class McpTimeouts {
  /// Creates limits. The defaults stay well within the 60 s of the agent
  /// loop.
  const McpTimeouts({
    this.connect = const Duration(seconds: 10),
    this.response = const Duration(seconds: 30),
    this.maxResponseBytes = 1024 * 1024,
    this.idleReconnect = const Duration(seconds: 15),
  });

  /// Until the response headers arrive.
  final Duration connect;

  /// Whole exchange (request until the answer is complete).
  final Duration response;

  /// Largest accepted response body (JSON or SSE stream of one request).
  final int maxResponseBytes;

  /// After this much idle time (or after a network failure) the next request
  /// opens a fresh connection (`Connection: close`) instead of reusing a
  /// pooled keep-alive socket that the server or a NAT may have dropped.
  final Duration idleReconnect;
}

/// Receives debug lines; they never contain header values or bodies.
typedef McpLog = void Function(String line);

/// Most same-origin redirects followed per request.
const maxRedirects = 3;

/// Runs [body] with cancellation via [cancel] and the overall time limit
/// [limit]: either fires the abort signal passed to [body] (which aborts the
/// HTTP request) and the call fails with [McpErrorKind.cancelled] or
/// [McpErrorKind.timeout]. Low-level errors are mapped to [McpException].
Future<T> guarded<T>(
  CancelToken? cancel,
  Duration limit,
  Future<T> Function(Future<void> abort) body,
) async {
  if (cancel?.isCancelled ?? false) {
    throw const McpException(McpErrorKind.cancelled, 'Abgebrochen');
  }
  final abort = Completer<void>();
  final failure = Completer<T>();
  void stop(McpException e) {
    if (!abort.isCompleted) abort.complete();
    if (!failure.isCompleted) failure.completeError(e);
  }

  final timer = Timer(
    limit,
    () => stop(
      McpException(
        McpErrorKind.timeout,
        'Keine Antwort innerhalb von ${limit.inSeconds} s',
      ),
    ),
  );
  unawaited(
    cancel?.whenCancelled.then(
      (_) => stop(const McpException(McpErrorKind.cancelled, 'Abgebrochen')),
    ),
  );
  final run = body(abort.future);
  try {
    return await Future.any([run, failure.future]);
  } on Object catch (e) {
    throw mapError(e);
  } finally {
    timer.cancel();
    if (!abort.isCompleted) abort.complete();
    // Spätere Fehler des abgebrochenen Laufs sind erwartet.
    unawaited(run.then((_) {}, onError: (Object _) {}));
    unawaited(failure.future.then((_) {}, onError: (Object _) {}));
  }
}

/// Maps transport errors onto [McpException].
McpException mapError(Object e) => switch (e) {
  McpException() => e,
  TimeoutException() => const McpException(
    McpErrorKind.timeout,
    'Server antwortet nicht (Zeitüberschreitung)',
  ),
  http.RequestAbortedException() => const McpException(
    McpErrorKind.cancelled,
    'Abgebrochen',
  ),
  SocketException(:final osError) => McpException(
    McpErrorKind.network,
    'Server nicht erreichbar${osError == null ? '' : ' (${osError.message})'}',
  ),
  HandshakeException() || TlsException() => const McpException(
    McpErrorKind.network,
    'TLS-Verbindung fehlgeschlagen',
  ),
  http.ClientException(:final message) => McpException(
    McpErrorKind.network,
    'Verbindung fehlgeschlagen: $message',
  ),
  FormatException() => const McpException(
    McpErrorKind.protocol,
    'Antwort nicht lesbar',
  ),
  _ => McpException(McpErrorKind.network, 'Verbindung fehlgeschlagen ($e)'),
};

/// Sends one HTTP request without automatic redirects; follows up to
/// [maxRedirects] redirects only to the same origin (method and body kept
/// for 307/308, otherwise `GET`). Waits at most [connect] for the headers.
/// [abort] aborts the request.
Future<http.StreamedResponse> sendRequest(
  http.Client client,
  String method,
  Uri url, {
  required Map<String, String> headers,
  required Duration connect,
  required Future<void> abort,
  String? body,
  McpLog? log,
}) async {
  var currentMethod = method;
  var currentUrl = url;
  var currentBody = body;
  for (var hop = 0; ; hop++) {
    final request =
        http.AbortableRequest(currentMethod, currentUrl, abortTrigger: abort)
          ..followRedirects = false
          ..headers.addAll(headers);
    if (currentBody != null) request.bodyBytes = utf8.encode(currentBody);
    log?.call('MCP: $currentMethod $currentUrl');
    final response = await client.send(request).timeout(connect);
    log?.call('MCP: HTTP ${response.statusCode}');
    if (!response.isRedirect &&
        !(response.statusCode >= 300 && response.statusCode < 400)) {
      return response;
    }
    unawaited(response.stream.listen(null).cancel());
    final location = response.headers['location'];
    if (location == null || hop >= maxRedirects) {
      throw McpException(
        McpErrorKind.protocol,
        'Ungültige Weiterleitung (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    final next = currentUrl.resolve(location);
    checkRedirect(url, next);
    if (response.statusCode != 307 && response.statusCode != 308) {
      currentMethod = 'GET';
      currentBody = null;
    }
    currentUrl = next;
  }
}

/// Reads [stream] completely; throws [McpErrorKind.tooLarge] beyond
/// [maxBytes].
Future<List<int>> readLimited(Stream<List<int>> stream, int maxBytes) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in limitBytes(stream, maxBytes)) {
    bytes.add(chunk);
  }
  return bytes.takeBytes();
}

/// [stream] that fails with [McpErrorKind.tooLarge] once more than
/// [maxBytes] have passed.
Stream<List<int>> limitBytes(Stream<List<int>> stream, int maxBytes) {
  var seen = 0;
  return stream.transform(
    StreamTransformer.fromHandlers(
      handleData: (chunk, sink) {
        seen += chunk.length;
        if (seen > maxBytes) {
          sink
            ..addError(
              McpException(
                McpErrorKind.tooLarge,
                'Antwort zu groß (über ${maxBytes ~/ 1024} KB)',
              ),
            )
            ..close();
          return;
        }
        sink.add(chunk);
      },
    ),
  );
}

/// Short, single-line excerpt of an error body for messages.
String excerpt(String body, [int max = 200]) {
  final single = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  return single.length <= max ? single : '${single.substring(0, max)}…';
}

/// Exception for a non-success HTTP status of an MCP or OAuth endpoint.
McpException httpFailure(int status, String body, {String? challenge}) {
  if (status == 401 || status == 403) {
    return McpException(
      McpErrorKind.authRequired,
      status == 401
          ? 'Anmeldung nötig (HTTP 401)'
          : 'Zugriff verweigert (HTTP 403)',
      statusCode: status,
      challenge: challenge,
    );
  }
  final detail = excerpt(body);
  return McpException(
    McpErrorKind.server,
    'Server-Fehler HTTP $status${detail.isEmpty ? '' : ': $detail'}',
    statusCode: status,
  );
}
