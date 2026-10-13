import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';

import '../errors.dart';
import '../protocol.dart';
import 'http_call.dart';
import 'transport.dart';

/// Streamable HTTP (MCP 2025-03-26 and newer): every message is a `POST` to
/// one endpoint; the answer comes as JSON or as an SSE stream that may carry
/// notifications and server requests first. No standing `GET` stream (the
/// connection exists only during a request).
final class StreamableHttpTransport extends TransportBase {
  /// Creates the transport for the endpoint [url].
  StreamableHttpTransport(super.url, super.deps);

  /// Session id assigned by the server (`Mcp-Session-Id`).
  String? get sessionId => _sessionId;
  String? _sessionId;

  String? _protocolVersion;

  @override
  bool get perOperation => false;

  @override
  set protocolVersion(String? version) => _protocolVersion = version;

  @override
  Future<void> open({CancelToken? cancel}) async {}

  // Pooled keep-alive sockets can be dead without the client knowing (server
  // restart, network change); a request on such a socket fails although the
  // server is fine. A `tools/call` may already have run when the connection
  // breaks and must not be repeated, so after a pause or a failure a `ping`
  // (idempotent, repeatable) tests the connection first.
  final Stopwatch _idle = Stopwatch();
  bool _suspect = false;

  bool _needsCheck() =>
      _suspect || (_idle.isRunning && _idle.elapsed >= deps.timeouts.idleCheck);

  Future<void> _verifyConnection(CancelToken? cancel) async {
    if (!_needsCheck()) return;
    for (var attempt = 0; ; attempt++) {
      try {
        await _roundTrip(
          'ping',
          null,
          cancel,
          limit: deps.timeouts.pingTimeout,
        );
        return;
      } on McpException catch (e) {
        if (e.kind == McpErrorKind.network && attempt == 0) continue;
        // A ping that fails again or times out means the server is not
        // reachable: report it instead of sending the `tools/call` anyway.
        if (e.kind == McpErrorKind.network ||
            e.kind == McpErrorKind.timeout ||
            e.kind == McpErrorKind.authRequired ||
            e.kind == McpErrorKind.sessionExpired) {
          rethrow;
        }
        // The server answered (even with an error): the connection is fine.
        return;
      }
    }
  }

  Future<Map<String, String>> _headers() async => {
    'content-type': 'application/json',
    'accept': 'application/json, text/event-stream',
    'mcp-session-id': ?_sessionId,
    'mcp-protocol-version': ?_protocolVersion,
    ...await deps.headers(),
  };

  @override
  Future<Object?> request(
    String method,
    Map<String, Object?>? params, {
    CancelToken? cancel,
  }) async {
    if (method == 'tools/call') await _verifyConnection(cancel);
    return _roundTrip(method, params, cancel);
  }

  Future<Object?> _roundTrip(
    String method,
    Map<String, Object?>? params,
    CancelToken? cancel, {
    Duration? limit,
  }) async {
    final id = nextId();
    final message = JsonRpcRequest(id, method, params);
    try {
      return await _exchange(message, id, cancel, limit);
    } on McpException catch (e) {
      if (e.kind == McpErrorKind.network) _suspect = true;
      rethrow;
    } finally {
      // Idle time counts from the end of the answer.
      _idle
        ..reset()
        ..start();
    }
  }

  Future<Object?> _exchange(
    JsonRpcRequest message,
    Object id,
    CancelToken? cancel,
    Duration? limit,
  ) {
    return guarded(cancel, limit ?? deps.timeouts.response, (abort) async {
      final response = await _post(message, abort);
      final type = response.headers['content-type'] ?? '';
      if (type.startsWith('text/event-stream')) {
        return TransportBase.resultOf(await _answerFromStream(response, id));
      }
      if (!type.startsWith('application/json')) {
        unawaited(response.stream.listen(null).cancel());
        throw McpException(
          McpErrorKind.protocol,
          'Unerwarteter Inhaltstyp "$type"',
        );
      }
      final body = utf8.decode(
        await readLimited(response.stream, deps.timeouts.maxResponseBytes),
        allowMalformed: true,
      );
      JsonRpcMessage? answer;
      for (final m in JsonRpcMessage.decode(body)) {
        if (TransportBase.answers(m, id)) {
          answer = m;
        } else {
          dispatch(m);
        }
      }
      if (answer == null) {
        throw const McpException(
          McpErrorKind.protocol,
          'Antwort passt zu keiner Anfrage',
        );
      }
      return TransportBase.resultOf(answer);
    });
  }

  @override
  Future<void> notify(
    String method,
    Map<String, Object?>? params, {
    CancelToken? cancel,
  }) => guarded(cancel, deps.timeouts.response, (abort) async {
    final response = await _post(JsonRpcNotification(method, params), abort);
    unawaited(response.stream.listen(null).cancel());
  });

  @override
  Future<void> sendAnswer(JsonRpcMessage message) =>
      guarded(null, deps.timeouts.response, (abort) async {
        final response = await _post(message, abort);
        unawaited(response.stream.listen(null).cancel());
      });

  /// POSTs [message]; returns a 2xx response or throws.
  Future<http.StreamedResponse> _post(
    JsonRpcMessage message,
    Future<void> abort,
  ) async {
    final hadSession = _sessionId != null;
    final http.StreamedResponse response;
    try {
      response = await sendRequest(
        deps.client,
        'POST',
        url,
        headers: await _headers(),
        body: message.encode(),
        connect: deps.timeouts.connect,
        abort: abort,
        log: deps.log,
      );
    } on Object {
      _suspect = true;
      rethrow;
    }
    _suspect = false;
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      final session = response.headers['mcp-session-id'];
      if (session != null && session.isNotEmpty) _sessionId = session;
      return response;
    }
    final body = utf8.decode(
      await readLimited(response.stream, 64 * 1024),
      allowMalformed: true,
    );
    if (status == 404 && hadSession) {
      _sessionId = null;
      throw const McpException(
        McpErrorKind.sessionExpired,
        'Sitzung abgelaufen',
        statusCode: 404,
      );
    }
    throw httpFailure(
      status,
      body,
      challenge: response.headers['www-authenticate'],
    );
  }

  Future<JsonRpcMessage> _answerFromStream(
    http.StreamedResponse response,
    Object id,
  ) async {
    final events = SseParser.parse(
      limitBytes(response.stream, deps.timeouts.maxResponseBytes),
    );
    await for (final event in events) {
      if (event.data.isEmpty) continue;
      for (final m in JsonRpcMessage.decode(event.data)) {
        // Die Antwort beendet den Stream (await for kündigt die Verbindung).
        if (TransportBase.answers(m, id)) return m;
        dispatch(m);
      }
    }
    throw const McpException(
      McpErrorKind.protocol,
      'Stream endete ohne Antwort',
    );
  }

  @override
  Future<void> close() async {
    final session = _sessionId;
    _sessionId = null;
    _protocolVersion = null;
    if (session == null) return;
    try {
      await guarded(null, deps.timeouts.connect, (abort) async {
        final response = await sendRequest(
          deps.client,
          'DELETE',
          url,
          headers: {'mcp-session-id': session, ...await deps.headers()},
          connect: deps.timeouts.connect,
          abort: abort,
          log: deps.log,
        );
        unawaited(response.stream.listen(null).cancel());
      });
    } on McpException catch (e) {
      // Der Server darf DELETE ablehnen (405); die Sitzung ist lokal vergessen.
      deps.log?.call('MCP: Sitzung beenden fehlgeschlagen: ${e.message}');
    }
  }
}
