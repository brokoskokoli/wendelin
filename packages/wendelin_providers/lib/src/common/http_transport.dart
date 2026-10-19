import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import 'exchange_tap.dart';
import 'http_errors.dart';
import 'http_settings.dart';
import 'redactor.dart';

/// Turns the SSE events of one response into [ChatEvent]s (adapter
/// specific). Throws a [ProviderException] for in-stream errors or
/// unreadable data.
abstract interface class StreamDecoder {
  /// Events for [event]; a terminal event ends the stream.
  List<ChatEvent> onEvent(SseEvent event);

  /// Called when the body ends; returns the remaining events, which must
  /// end with a terminal event (or throws).
  List<ChatEvent> onEnd();
}

/// Builds the request for attempt [attempt] (0-based). The request must
/// honour [abortTrigger] (e.g. `http.AbortableRequest`).
typedef RequestBuilder = Future<http.BaseRequest> Function(
  int attempt,
  Future<void> abortTrigger,
);

/// Maps a non-2xx response onto an exception.
typedef HttpErrorMapper = ProviderException Function(
  int status,
  String body,
  Duration? retryAfter,
);

/// Decides whether a failed attempt is retried with the next attempt number.
typedef RetryPolicy = bool Function(int status, String body, int attempt);

/// Shared HTTP plumbing: sending with cancellation and timeouts, SSE
/// decoding, error mapping and secret redaction.
final class HttpTransport {
  /// Creates a transport.
  HttpTransport({
    required this.client,
    required this.settings,
    required this.label,
    required this.redactor,
  });

  /// The injected HTTP client.
  final http.Client client;

  /// Timeouts, clock, log.
  final HttpSettings settings;

  /// Provider name used in error messages.
  final String label;

  /// Removes secrets from every error message and log line.
  final Redactor redactor;

  static const _maxErrorBody = 64 * 1024;

  /// Writes a redacted debug line.
  void log(String line) => settings.log?.call(redactor.apply(line));

  /// Streams a chat response according to the `LlmProvider.chat` contract:
  /// exactly one terminal event, never a stream error, cancellation via
  /// [cancel] aborts the HTTP request and ends with
  /// `ErrorEvent(CancelledException)`.
  Stream<ChatEvent> stream({
    required RequestBuilder build,
    required StreamDecoder Function() decoder,
    required HttpErrorMapper onHttpError,
    RetryPolicy? retry,
    CancelToken? cancel,
    ExchangeTap? tap,
    void Function(Map<String, String> headers)? checkHead,
    Stream<List<int>> Function(Stream<List<int>> raw)? openBody,
    Stream<List<int>> Function(
      Map<String, String> headers,
      Stream<List<int>> raw,
    )?
    openErrorBody,
    void Function()? onEnd,
  }) {
    final token = cancel ?? CancelToken();
    final abort = Completer<void>();
    late final StreamController<ChatEvent> out;
    StreamSubscription<SseEvent>? sub;
    var finished = false;

    void abortRequest() {
      if (!abort.isCompleted) abort.complete();
    }

    void finish(ChatEvent terminal, {bool abortHttp = false}) {
      if (finished) return;
      finished = true;
      onEnd?.call();
      tap?.end(completed: terminal is Done);
      var event = terminal;
      if (terminal is ErrorEvent) {
        final error = redactor.redact(terminal.error);
        log('$label: Fehler ${error.runtimeType}: ${error.message}');
        event = ErrorEvent(error);
      }
      out.add(event);
      unawaited(out.close());
      unawaited(sub?.cancel());
      sub = null;
      if (abortHttp) abortRequest();
    }

    void emitAll(List<ChatEvent> events) {
      for (final e in events) {
        if (finished) return;
        e.isTerminal ? finish(e) : out.add(e);
      }
    }

    void fail(Object error) =>
        finish(ErrorEvent(exceptionForError(error, label: label)));

    Future<void> run() async {
      if (token.isCancelled) {
        finish(const ErrorEvent(CancelledException()));
        return;
      }
      unawaited(
        token.whenCancelled.then(
          (_) =>
              finish(const ErrorEvent(CancelledException()), abortHttp: true),
        ),
      );
      try {
        for (var attempt = 0; ; attempt++) {
          final request = await build(attempt, abort.future);
          if (finished) return;
          if (tap != null && request is http.Request) {
            tap.request(request.bodyBytes);
          }
          log('$label: ${request.method} ${request.url}');
          final response = await client
              .send(request)
              .timeout(
                settings.responseTimeout,
                onTimeout: () {
                  abortRequest();
                  throw TimeoutException('response');
                },
              );
          if (finished) {
            unawaited(response.stream.listen(null).cancel());
            return;
          }
          log('$label: HTTP ${response.statusCode}');
          tap?.head(response.statusCode, response.headers);
          if (response.statusCode >= 200 && response.statusCode < 300) {
            if (checkHead != null) {
              try {
                checkHead(response.headers);
              } on Object {
                unawaited(response.stream.listen(null).cancel());
                rethrow;
              }
            }
            _listen(
              response,
              decoder(),
              emitAll,
              fail,
              (s) => sub = s,
              () {
                if (!finished) abortRequest();
              },
              tap,
              openBody,
            );
            return;
          }
          final body = await _readBody(response, openErrorBody);
          if (finished) return;
          if (retry != null && retry(response.statusCode, body, attempt)) {
            log('$label: neuer Versuch');
            continue;
          }
          finish(
            ErrorEvent(
              onHttpError(
                response.statusCode,
                body,
                parseRetryAfter(response.headers, settings.clock.now()),
              ),
            ),
          );
          return;
        }
      } on Object catch (e) {
        fail(e);
      }
    }

    out = StreamController<ChatEvent>(
      onListen: () => unawaited(run()),
      onCancel: () {
        // Consumer stopped: stop everything, emit nothing.
        finished = true;
        onEnd?.call();
        abortRequest();
        final s = sub;
        sub = null;
        return s?.cancel();
      },
    );
    return out.stream;
  }

  void _listen(
    http.StreamedResponse response,
    StreamDecoder dec,
    void Function(List<ChatEvent>) emitAll,
    void Function(Object) fail,
    void Function(StreamSubscription<SseEvent>) setSub,
    void Function() onIdleTimeout,
    ExchangeTap? tap,
    Stream<List<int>> Function(Stream<List<int>> raw)? openBody,
  ) {
    final wireBytes = tap == null
        ? response.stream
        : response.stream.map((chunk) {
            tap.chunk(chunk);
            return chunk;
          });
    final source = openBody == null ? wireBytes : openBody(wireBytes);
    final body = source.timeout(
      settings.idleTimeout,
      onTimeout: (sink) {
        onIdleTimeout();
        sink
          ..addError(TimeoutException('idle'))
          ..close();
      },
    );
    setSub(
      SseParser.parse(body).listen(
        (event) {
          try {
            emitAll(dec.onEvent(event));
          } on Object catch (e) {
            fail(e);
          }
        },
        onError: fail,
        onDone: () {
          try {
            emitAll(dec.onEnd());
          } on Object catch (e) {
            fail(e);
          }
        },
        cancelOnError: true,
      ),
    );
  }

  Future<String> _readBody(
    http.StreamedResponse response, [
    Stream<List<int>> Function(Map<String, String>, Stream<List<int>>)? open,
  ]) async {
    final bytes = <int>[];
    final source = open == null
        ? response.stream
        : open(response.headers, response.stream);
    await for (final chunk in source.timeout(settings.idleTimeout)) {
      bytes.addAll(chunk);
      if (bytes.length > _maxErrorBody) break;
    }
    return utf8.decode(
      bytes.length > _maxErrorBody ? bytes.sublist(0, _maxErrorBody) : bytes,
      allowMalformed: true,
    );
  }

  /// Sends a GET and decodes the JSON object body. Throws a redacted
  /// [ProviderException] on failure.
  Future<Map<String, Object?>> getJson(
    Uri url,
    Map<String, String> headers, {
    required HttpErrorMapper onHttpError,
  }) async {
    try {
      log('$label: GET $url');
      final response = await client
          .get(url, headers: headers)
          .timeout(settings.responseTimeout);
      log('$label: HTTP ${response.statusCode}');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw onHttpError(
          response.statusCode,
          response.body,
          parseRetryAfter(response.headers, settings.clock.now()),
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, Object?>) {
        throw MalformedResponseException('$label: JSON-Objekt erwartet');
      }
      return decoded;
    } on Object catch (e) {
      throw redactor.redact(exceptionForError(e, label: label));
    }
  }

  /// Sends a GET and returns the body bytes (at most [maxBytes], more is a
  /// [MalformedResponseException]). Throws a redacted [ProviderException]
  /// on failure.
  Future<Uint8List> getBytes(
    Uri url,
    Map<String, String> headers, {
    required int maxBytes,
    required HttpErrorMapper onHttpError,
  }) async {
    try {
      log('$label: GET $url');
      final response = await client
          .send(http.Request('GET', url)..headers.addAll(headers))
          .timeout(settings.responseTimeout);
      log('$label: HTTP ${response.statusCode}');
      final builder = BytesBuilder(copy: false);
      var oversize = false;
      await for (final chunk in response.stream.timeout(
        settings.responseTimeout,
      )) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          oversize = true;
          break;
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bytes = builder.takeBytes();
        throw onHttpError(
          response.statusCode,
          utf8.decode(
            bytes.length > _maxErrorBody
                ? bytes.sublist(0, _maxErrorBody)
                : bytes,
            allowMalformed: true,
          ),
          parseRetryAfter(response.headers, settings.clock.now()),
        );
      }
      if (oversize) {
        throw MalformedResponseException('$label: Antwort zu groß');
      }
      return builder.takeBytes();
    } on Object catch (e) {
      throw redactor.redact(exceptionForError(e, label: label));
    }
  }
}
