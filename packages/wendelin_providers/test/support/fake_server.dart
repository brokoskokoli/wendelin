import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reads `test/fixtures/<path>`.
String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

/// One scripted answer of [FakeServer].
sealed class FakeResponse {
  const FakeResponse();

  /// A 200 `text/event-stream` body, delivered in chunks of [chunkSize]
  /// bytes (to exercise chunk boundaries).
  const factory FakeResponse.sse(String body, {int chunkSize}) = _Sse;

  /// A complete response with [status] and [body].
  const factory FakeResponse.json(
    int status,
    String body, {
    Map<String, String> headers,
  }) = _Json;

  /// A 200 stream that sends [prefix] and then never ends.
  const factory FakeResponse.hang(String prefix) = _Hang;

  /// A response whose headers never arrive.
  const factory FakeResponse.never() = _Never;

  /// The client throws [error] instead of answering.
  const factory FakeResponse.fail(Object error) = _Fail;
}

final class _Sse extends FakeResponse {
  const _Sse(this.body, {this.chunkSize = 7});
  final String body;
  final int chunkSize;
}

final class _Json extends FakeResponse {
  const _Json(this.status, this.body, {this.headers = const {}});
  final int status;
  final String body;
  final Map<String, String> headers;
}

final class _Hang extends FakeResponse {
  const _Hang(this.prefix);
  final String prefix;
}

final class _Never extends FakeResponse {
  const _Never();
}

final class _Fail extends FakeResponse {
  const _Fail(this.error);
  final Object error;
}

/// A recorded request.
final class RecordedRequest {
  RecordedRequest(this.method, this.url, this.headers, this.body);

  /// HTTP method.
  final String method;

  /// Full URL.
  final Uri url;

  /// Request headers.
  final Map<String, String> headers;

  /// Body as text.
  final String body;

  /// Body decoded as JSON object.
  Map<String, Object?> get json => jsonDecode(body) as Map<String, Object?>;
}

/// Mock HTTP server: answers requests with scripted [FakeResponse]s in
/// order and records them.
final class FakeServer {
  /// Creates a server with [responses].
  FakeServer(List<FakeResponse> responses) : _responses = List.of(responses);

  final List<FakeResponse> _responses;

  /// Requests received so far.
  final List<RecordedRequest> requests = [];

  /// Whether a hanging body stream was cancelled by the client.
  bool bodyCancelled = false;

  /// Whether the abort trigger of a request fired.
  bool aborted = false;

  /// The client to inject into adapters.
  late final http.Client client = MockClient.streaming(_handle);

  Future<http.StreamedResponse> _handle(
    http.BaseRequest request,
    http.ByteStream bodyStream,
  ) async {
    final body = utf8.decode(await bodyStream.toBytes());
    requests.add(
      RecordedRequest(
        request.method,
        request.url,
        Map.of(request.headers),
        body,
      ),
    );
    if (request is http.Abortable) {
      unawaited(request.abortTrigger?.then((_) => aborted = true));
    }
    if (_responses.isEmpty) {
      throw StateError('FakeServer: keine Antwort mehr');
    }
    final response = _responses.removeAt(0);
    switch (response) {
      case _Sse(:final body, :final chunkSize):
        final bytes = utf8.encode(body);
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < bytes.length; i += chunkSize)
              bytes.sublist(
                i,
                i + chunkSize > bytes.length ? bytes.length : i + chunkSize,
              ),
          ]),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      case _Json(:final status, :final body, :final headers):
        return http.StreamedResponse(
          Stream.value(utf8.encode(body)),
          status,
          headers: {'content-type': 'application/json', ...headers},
        );
      case _Hang(:final prefix):
        // Never closed on purpose: the body hangs until the client cancels.
        // ignore: close_sinks
        final controller = StreamController<List<int>>(
          onCancel: () => bodyCancelled = true,
        );
        controller.add(utf8.encode(prefix));
        return http.StreamedResponse(controller.stream, 200);
      case _Never():
        return Completer<http.StreamedResponse>().future;
      case _Fail(:final error):
        throw error;
    }
  }
}
