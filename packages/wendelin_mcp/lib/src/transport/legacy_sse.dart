import 'dart:async';
import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import '../errors.dart';
import '../net_policy.dart';
import '../protocol.dart';
import 'http_call.dart';
import 'transport.dart';

/// Legacy HTTP+SSE (MCP 2024-11-05): a `GET` opens an event stream whose
/// first `endpoint` event names the URL for `POST`s; answers arrive on the
/// stream. The stream stays open only for one operation ([open] …
/// [close]); the session ends with it.
final class LegacySseTransport extends TransportBase {
  /// Creates the transport for the SSE URL [url].
  LegacySseTransport(super.url, super.deps);

  Uri? _endpoint;
  StreamSubscription<SseEvent>? _sub;
  Completer<void>? _abort;
  final Map<Object, Completer<JsonRpcMessage>> _pending = {};
  McpException? _streamError;

  @override
  bool get perOperation => true;

  @override
  set protocolVersion(String? version) {}

  /// Whether the event stream is open.
  bool get isOpen => _sub != null;

  @override
  Future<void> open({CancelToken? cancel}) async {
    if (_sub != null) return;
    final abort = Completer<void>();
    final endpoint = Completer<Uri>();
    _abort = abort;
    _streamError = null;
    try {
      var opened = false;
      await guarded(cancel, deps.timeouts.connect, (connectAbort) async {
        unawaited(
          connectAbort.then((_) {
            if (!opened) _abortStream();
          }),
        );
        final response = await sendRequest(
          deps.client,
          'GET',
          url,
          headers: {'accept': 'text/event-stream', ...await deps.headers()},
          connect: deps.timeouts.connect,
          abort: abort.future,
          log: deps.log,
        );
        final type = response.headers['content-type'] ?? '';
        if (response.statusCode != 200 ||
            !type.startsWith('text/event-stream')) {
          final body = utf8.decode(
            await readLimited(response.stream, 64 * 1024),
            allowMalformed: true,
          );
          if (response.statusCode == 200) {
            throw const McpException(
              McpErrorKind.protocol,
              'Kein SSE-Stream (Legacy-SSE)',
            );
          }
          throw httpFailure(
            response.statusCode,
            body,
            challenge: response.headers['www-authenticate'],
          );
        }
        // Byte-Limit vor dem Parser: auch eine endlose Zeile ohne
        // Ereignisende bleibt begrenzt (über die Dauer eines Vorgangs).
        _sub =
            SseParser.parse(
              limitBytes(response.stream, deps.timeouts.maxResponseBytes),
            ).listen(
              (event) => _onEvent(event, endpoint),
              onError: (Object e) => _fail(mapError(e), endpoint),
              onDone: () => _fail(
                const McpException(
                  McpErrorKind.network,
                  'Server hat den SSE-Stream beendet',
                ),
                endpoint,
              ),
              cancelOnError: true,
            );
        _endpoint = await endpoint.future;
        opened = true;
      });
    } on Object {
      await close();
      rethrow;
    }
  }

  void _abortStream() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  void _onEvent(SseEvent event, Completer<Uri> endpoint) {
    if (event.event == 'endpoint') {
      if (endpoint.isCompleted) return;
      final target = url.resolve(event.data.trim());
      try {
        checkRedirect(url, target);
      } on McpException catch (e) {
        _fail(e, endpoint);
        return;
      }
      endpoint.complete(target);
      return;
    }
    if (event.event != null && event.event != 'message') return;
    try {
      for (final m in JsonRpcMessage.decode(event.data)) {
        final id = switch (m) {
          JsonRpcResponse(:final id) => id,
          JsonRpcError(:final id) => id,
          _ => null,
        };
        final waiting = id == null ? null : _pending.remove(id);
        if (waiting != null) {
          waiting.complete(m);
        } else {
          dispatch(m);
        }
      }
    } on McpException catch (e) {
      _fail(e, endpoint);
    }
  }

  void _fail(McpException error, Completer<Uri> endpoint) {
    _streamError ??= error;
    if (!endpoint.isCompleted) endpoint.completeError(error);
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(error);
    }
    _pending.clear();
    unawaited(close());
  }

  Uri _requireEndpoint() {
    final error = _streamError;
    if (error != null) throw error;
    final endpoint = _endpoint;
    if (endpoint == null) {
      throw const McpException(
        McpErrorKind.protocol,
        'Legacy-SSE: Verbindung nicht geöffnet',
      );
    }
    return endpoint;
  }

  @override
  Future<Object?> request(
    String method,
    Map<String, Object?>? params, {
    CancelToken? cancel,
  }) {
    final id = nextId();
    return guarded(cancel, deps.timeouts.response, (abort) async {
      final endpoint = _requireEndpoint();
      final answer = Completer<JsonRpcMessage>();
      _pending[id] = answer;
      // Fehler können vor dem await unten eintreffen.
      unawaited(answer.future.then((_) {}, onError: (Object _) {}));
      unawaited(abort.then((_) => _pending.remove(id)));
      await _post(endpoint, JsonRpcRequest(id, method, params), abort);
      return TransportBase.resultOf(await answer.future);
    });
  }

  @override
  Future<void> notify(
    String method,
    Map<String, Object?>? params, {
    CancelToken? cancel,
  }) => guarded(cancel, deps.timeouts.response, (abort) async {
    await _post(_requireEndpoint(), JsonRpcNotification(method, params), abort);
  });

  @override
  Future<void> sendAnswer(JsonRpcMessage message) =>
      guarded(null, deps.timeouts.response, (abort) async {
        await _post(_requireEndpoint(), message, abort);
      });

  Future<void> _post(
    Uri endpoint,
    JsonRpcMessage message,
    Future<void> abort,
  ) async {
    final response = await sendRequest(
      deps.client,
      'POST',
      endpoint,
      headers: {'content-type': 'application/json', ...await deps.headers()},
      body: message.encode(),
      connect: deps.timeouts.connect,
      abort: abort,
      log: deps.log,
    );
    final body = utf8.decode(
      await readLimited(response.stream, 64 * 1024),
      allowMalformed: true,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw httpFailure(
        response.statusCode,
        body,
        challenge: response.headers['www-authenticate'],
      );
    }
  }

  @override
  Future<void> close() async {
    _endpoint = null;
    _abortStream();
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(
          const McpException(McpErrorKind.network, 'Verbindung geschlossen'),
        );
      }
    }
    _pending.clear();
    final cancelling = _sub?.cancel();
    _sub = null;
    await cancelling;
  }
}
