import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../errors.dart';
import '../protocol.dart';
import 'http_call.dart';

/// Supplies the auth headers for each HTTP request (resolved from
/// `McpSecrets`, possibly after a token refresh).
typedef HeaderSource = Future<Map<String, String>> Function();

/// Everything a transport needs besides the URL.
final class McpTransportDeps {
  /// Creates the dependencies.
  McpTransportDeps({
    required this.client,
    required this.headers,
    this.timeouts = const McpTimeouts(),
    this.log,
  });

  /// HTTP client (injected; tests use a real one against `FakeMcpServer`).
  final http.Client client;

  /// Auth headers.
  final HeaderSource headers;

  /// Limits.
  final McpTimeouts timeouts;

  /// Debug log (method and URL only).
  final McpLog? log;
}

/// Carries JSON-RPC messages to one MCP server.
///
/// Contract (checked by `mcpClientContract`): [request] returns the
/// `result` of the matching answer or throws [McpException]
/// ([McpErrorKind.server] with `rpcCode` for JSON-RPC errors); messages that
/// arrive meanwhile go to [notifications]; server requests are answered
/// (`ping` with an empty result, everything else with
/// [rpcMethodNotFound]); cancellation and time limits end the call with
/// [McpErrorKind.cancelled] / [McpErrorKind.timeout].
abstract interface class McpTransport {
  /// Whether the session lives only as long as one connection (Legacy-SSE):
  /// the client then initializes for every operation.
  bool get perOperation;

  /// Protocol version for the `MCP-Protocol-Version` header (set after
  /// `initialize`).
  set protocolVersion(String? version);

  /// Opens what the transport needs before requests (Legacy-SSE: the event
  /// stream and its `endpoint`); no-op for Streamable HTTP.
  Future<void> open({CancelToken? cancel});

  /// Sends [method] and returns the result.
  Future<Object?> request(
    String method,
    Map<String, Object?>? params, {
    CancelToken? cancel,
  });

  /// Sends a notification.
  Future<void> notify(
    String method,
    Map<String, Object?>? params, {
    CancelToken? cancel,
  });

  /// Notifications from the server.
  Stream<JsonRpcNotification> get notifications;

  /// Ends the session (Streamable HTTP: `DELETE`; Legacy-SSE: closes the
  /// stream). Never throws.
  Future<void> close();
}

/// Shared bookkeeping of both transports: request ids, notification
/// stream, answers to server requests.
abstract base class TransportBase implements McpTransport {
  /// Creates the base.
  TransportBase(this.url, this.deps);

  /// Server URL.
  final Uri url;

  /// Dependencies.
  final McpTransportDeps deps;

  final StreamController<JsonRpcNotification> _notifications =
      StreamController.broadcast(sync: true);

  var _nextId = 1;

  /// Next request id.
  int nextId() => _nextId++;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  /// Sends [message] (an answer to a server request) back to the server.
  Future<void> sendAnswer(JsonRpcMessage message);

  /// Routes a received non-answer message: notifications to
  /// [notifications], server requests get an answer.
  void dispatch(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcNotification():
        if (!_notifications.isClosed) _notifications.add(message);
      case JsonRpcRequest(:final id, :final method):
        final answer = method == 'ping'
            ? JsonRpcResponse(id, const <String, Object?>{})
            : JsonRpcError(id, rpcMethodNotFound, 'Nicht unterstützt: $method');
        unawaited(
          sendAnswer(answer).catchError((Object e) {
            deps.log?.call('MCP: Antwort an Server fehlgeschlagen: $e');
          }),
        );
      case JsonRpcResponse() || JsonRpcError():
        break;
    }
  }

  /// The result of [answer] or the matching [McpException].
  static Object? resultOf(JsonRpcMessage answer) => switch (answer) {
    JsonRpcResponse(:final result) => result,
    JsonRpcError(:final code, :final message) => throw McpException(
      McpErrorKind.server,
      'Server meldet Fehler $code: ${excerpt(message)}',
      rpcCode: code,
    ),
    _ => throw const McpException(McpErrorKind.protocol, 'Keine Antwort'),
  };

  /// Whether [m] answers the request [id].
  static bool answers(JsonRpcMessage m, Object id) => switch (m) {
    JsonRpcResponse(id: final i) => i == id,
    JsonRpcError(id: final i) => i == id,
    _ => false,
  };
}
