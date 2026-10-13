import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'config.dart';
import 'errors.dart';
import 'net_policy.dart';
import 'oauth/oauth_flow.dart';
import 'ports.dart';
import 'protocol.dart';
import 'transport/http_call.dart';
import 'transport/legacy_sse.dart';
import 'transport/streamable_http.dart';
import 'transport/transport.dart';

/// Creates the transport of [kind] (`streamable` or `sse`) for [url].
typedef McpTransportFactory = McpTransport Function(
  McpTransportKind kind,
  Uri url,
  McpTransportDeps deps,
);

McpTransport _defaultFactory(
  McpTransportKind kind,
  Uri url,
  McpTransportDeps deps,
) => kind == McpTransportKind.sse
    ? LegacySseTransport(url, deps)
    : StreamableHttpTransport(url, deps);

/// Most tools [McpClient.listTools] collects from one server.
const maxListedTools = 1024;

/// Result of [McpClient.probe].
enum McpReachability {
  /// `initialize` succeeded.
  reachable,

  /// The server wants credentials (or the stored ones are invalid).
  authRequired,

  /// No connection (network, timeout, refused address).
  unreachable,

  /// Something answered, but not as an MCP server.
  protocolError,
}

/// Status of a server for the settings screen.
@immutable
final class McpProbeResult {
  /// Creates a probe result.
  const McpProbeResult({
    required this.status,
    required this.latency,
    this.server,
    this.detail,
    this.transport,
  });

  /// Outcome.
  final McpReachability status;

  /// Time the probe took.
  final Duration latency;

  /// Server info, if reachable.
  final McpServerInfo? server;

  /// German reason, if not reachable.
  final String? detail;

  /// The transport in use (after auto detection).
  final McpTransportKind? transport;

  @override
  String toString() =>
      'McpProbeResult(${status.name}, ${latency.inMilliseconds} ms, $detail)';
}

/// MCP client for one server: lifecycle (`initialize`,
/// `notifications/initialized`), `tools/list` with pagination and cache,
/// `tools/call`, `ping`, reachability probe.
///
/// Connects only on demand: Streamable HTTP keeps just the session id
/// between calls, Legacy-SSE opens its event stream per operation. With
/// [McpTransportKind.auto] Streamable HTTP is tried first; if the server
/// answers the `POST` with 400/404/405 and a `GET` yields an `endpoint` event,
/// Legacy-SSE is used from then on.
///
/// Secrets are resolved per request through [secrets] (or [oauth]) and are
/// removed from every exception message and log line.
final class McpClient {
  /// Creates a client for [config].
  McpClient({
    required this.config,
    required http.Client httpClient,
    required this.secrets,
    this.oauth,
    this.cache,
    this.clock = const SystemClock(),
    this.timeouts = const McpTimeouts(),
    this.cacheMaxAge = const Duration(hours: 24),
    this.clientName = 'Wendelin',
    this.clientVersion = '0.1.0',
    McpLog? log,
    McpTransportFactory? transportFactory,
  }) : _http = httpClient,
       _rawLog = log,
       _factory = transportFactory ?? _defaultFactory;

  /// The server.
  final McpServerConfig config;

  /// Secret access (bearer token, header values).
  final McpSecrets secrets;

  /// OAuth flow, for servers with [McpOAuth].
  final McpOAuthFlow? oauth;

  /// Persistence of the tool list.
  final McpCacheStore? cache;

  /// Time source (cache age).
  final Clock clock;

  /// Limits.
  final McpTimeouts timeouts;

  /// How long a cached tool list is used without asking the server.
  final Duration cacheMaxAge;

  /// `clientInfo.name` in `initialize`.
  final String clientName;

  /// `clientInfo.version` in `initialize`.
  final String clientVersion;

  final http.Client _http;
  final McpLog? _rawLog;
  final McpTransportFactory _factory;
  final Set<String> _secretValues = {};
  final StreamController<void> _toolsChanged =
      StreamController<void>.broadcast();

  McpTransportKind? _detected;
  StreamableHttpTransport? _streamable;
  McpTransport? _session;
  Future<void>? _initializing;
  McpServerInfo? _serverInfo;
  McpToolCache? _cached;
  var _toolsStale = false;
  String? _lastChallenge;

  /// Info from the last successful `initialize`.
  McpServerInfo? get serverInfo => _serverInfo;

  /// Transport in use: configured, or detected with `auto` (`null` until the
  /// first contact).
  McpTransportKind? get transport =>
      config.transport == McpTransportKind.auto ? _detected : config.transport;

  /// The `WWW-Authenticate` header of the last 401/403 (for
  /// [McpOAuthFlow.authorize]).
  String? get lastChallenge => _lastChallenge;

  /// Emits when the server reported `notifications/tools/list_changed`; the
  /// next [listTools] asks the server again.
  Stream<void> get toolsChanged => _toolsChanged.stream;

  void _log(String line) => _rawLog?.call(redact(line));

  /// [text] with every secret value this client has sent replaced by `***`.
  String redact(String text) {
    var out = text;
    for (final s in _secretValues) {
      if (s.length >= 4) out = out.replaceAll(s, '***');
    }
    return out;
  }

  McpException _redacted(McpException e) {
    final m = redact(e.message);
    return m == e.message ? e : e.withMessage(m);
  }

  Future<String> _secret(String ref, String what) async {
    final value = await secrets.read(ref);
    if (value == null || value.isEmpty) {
      throw McpException(McpErrorKind.authRequired, '$what fehlt');
    }
    _secretValues.add(value);
    return value;
  }

  Future<Map<String, String>> _headers({bool forceRefresh = false}) async {
    switch (config.auth) {
      case McpNoAuth():
        return const {};
      case McpBearerAuth(:final secretRef):
        return {'authorization': 'Bearer ${await _secret(secretRef, 'Token')}'};
      case McpHeadersAuth(:final secretRefsByHeader):
        return {
          for (final MapEntry(key: header, value: ref)
              in secretRefsByHeader.entries)
            header: await _secret(ref, 'Wert für Header „$header“'),
        };
      case McpOAuth():
        final flow = oauth;
        if (flow == null) {
          throw const McpException(
            McpErrorKind.authRequired,
            'OAuth ist nicht eingerichtet',
          );
        }
        // Ohne Anmeldung unauthentifiziert anfragen: Die 401-Antwort liefert
        // die Challenge für die Discovery.
        if (!forceRefresh && await flow.storedTokens(config) == null) {
          return const {};
        }
        final token = await flow.accessToken(
          config,
          forceRefresh: forceRefresh,
        );
        _secretValues.add(token);
        return {'authorization': 'Bearer $token'};
    }
  }

  McpTransport _newTransport(McpTransportKind kind) {
    final transport = _factory(
      kind,
      config.url,
      McpTransportDeps(
        client: _http,
        headers: _headers,
        timeouts: timeouts,
        log: _log,
      ),
    );
    transport.notifications.listen(_onNotification);
    return transport;
  }

  void _onNotification(JsonRpcNotification n) {
    _log('MCP: Benachrichtigung ${n.method}');
    if (n.method == 'notifications/tools/list_changed') {
      _toolsStale = true;
      if (!_toolsChanged.isClosed) _toolsChanged.add(null);
    }
  }

  Future<void> _handshake(McpTransport t, CancelToken? cancel) async {
    final result = await t.request('initialize', {
      'protocolVersion': mcpProtocolVersions.first,
      // Nur Tools: keine Client-Fähigkeiten (Sampling, Roots, Elicitation).
      'capabilities': const <String, Object?>{},
      'clientInfo': {'name': clientName, 'version': clientVersion},
    }, cancel: cancel);
    final info = McpServerInfo.fromResult(result);
    t.protocolVersion = info.protocolVersion;
    await t.notify('notifications/initialized', null, cancel: cancel);
    _serverInfo = info;
  }

  Future<void> _ensureSession(McpTransport t, CancelToken? cancel) async {
    while (!identical(_session, t)) {
      final pending = _initializing;
      if (pending != null) {
        await pending;
        continue;
      }
      final run = _handshake(t, cancel).then((_) => _session = t);
      _initializing = run;
      try {
        await run;
      } finally {
        _initializing = null;
      }
    }
  }

  Future<McpTransportKind> _kind(CancelToken? cancel) async {
    if (config.transport != McpTransportKind.auto) return config.transport;
    final known = _detected;
    if (known != null) return known;
    final streamable = _streamable ??=
        _newTransport(McpTransportKind.streamable) as StreamableHttpTransport;
    try {
      await _ensureSession(streamable, cancel);
      return _detected = McpTransportKind.streamable;
    } on McpException catch (e) {
      final status = e.statusCode;
      // Rückwärtskompatibilität laut Spezifikation: 400, 404 oder 405 auf den
      // POST deuten auf einen reinen Legacy-SSE-Server.
      if (e.kind != McpErrorKind.server ||
          (status != 400 && status != 404 && status != 405)) {
        rethrow;
      }
      _log('MCP: POST abgelehnt (HTTP $status), versuche Legacy-SSE');
      final legacy = _newTransport(McpTransportKind.sse);
      try {
        await legacy.open(cancel: cancel);
      } on McpException {
        throw e;
      } finally {
        await legacy.close();
      }
      return _detected = McpTransportKind.sse;
    }
  }

  Future<T> _run<T>(
    Future<T> Function(McpTransport t) op, {
    CancelToken? cancel,
    bool idempotent = false,
  }) async {
    try {
      checkServerUrl(config.url);
      try {
        return await _attempt(op, cancel, idempotent: idempotent);
      } on McpException catch (e) {
        if (e.kind != McpErrorKind.authRequired || e.statusCode == null) {
          rethrow;
        }
        _lastChallenge = e.challenge;
        final flow = oauth;
        if (config.auth is! McpOAuth ||
            flow == null ||
            await flow.storedTokens(config) == null) {
          rethrow;
        }
        // Token vom Server abgelehnt: einmal erneuern und wiederholen.
        await _headers(forceRefresh: true);
        _session = null;
        return await _attempt(op, cancel, idempotent: idempotent);
      }
    } on McpException catch (e) {
      if (e.kind == McpErrorKind.authRequired && e.challenge != null) {
        _lastChallenge = e.challenge;
      }
      _log('MCP: Fehler ${e.kind.name}: ${e.message}');
      throw _redacted(e);
    }
  }

  Future<T> _attempt<T>(
    Future<T> Function(McpTransport t) op,
    CancelToken? cancel, {
    bool idempotent = false,
  }) async {
    final kind = await _kind(cancel);
    if (kind == McpTransportKind.sse) {
      final t = _newTransport(McpTransportKind.sse);
      try {
        await t.open(cancel: cancel);
        await _handshake(t, cancel);
        return await op(t);
      } finally {
        await t.close();
      }
    }
    final t = _streamable ??=
        _newTransport(McpTransportKind.streamable) as StreamableHttpTransport;
    for (var attempt = 0; ; attempt++) {
      await _ensureSession(t, cancel);
      try {
        return await op(t);
      } on McpException catch (e) {
        final lost =
            e.kind == McpErrorKind.sessionExpired ||
            (idempotent && e.kind == McpErrorKind.network);
        if (!lost || attempt > 0) rethrow;
        _log('MCP: Verbindung/Sitzung verloren, neu initialisieren');
        _session = null;
      }
    }
  }

  /// Connects and runs `initialize` (again), e.g. after a configuration
  /// change.
  Future<McpServerInfo> initialize({CancelToken? cancel}) async {
    _session = null;
    await _run((_) async {}, cancel: cancel);
    return _serverInfo!;
  }

  /// All tools of the server (all pages of `tools/list`). Uses the cache
  /// unless [refresh] is set, the cache is older than [cacheMaxAge] or the
  /// server reported `list_changed`.
  Future<List<McpToolInfo>> listTools({
    bool refresh = false,
    CancelToken? cancel,
  }) async {
    if (!refresh && !_toolsStale) {
      final cached = _cached ?? await cache?.read(config.id);
      if (cached != null &&
          clock.now().difference(cached.fetchedAt) < cacheMaxAge) {
        _cached = cached;
        return cached.tools;
      }
    }
    _toolsStale = false;
    final tools = await _run((t) async {
      final all = <McpToolInfo>[];
      String? cursor;
      for (var page = 0; ; page++) {
        if (page >= 100) {
          throw const McpException(
            McpErrorKind.protocol,
            'tools/list: zu viele Seiten',
          );
        }
        final result = await t.request('tools/list', {
          'cursor': ?cursor,
        }, cancel: cancel);
        if (result is! Map<String, Object?> ||
            result['tools'] is! List<Object?>) {
          throw const McpException(
            McpErrorKind.protocol,
            'tools/list: Liste fehlt',
          );
        }
        for (final entry in result['tools']! as List<Object?>) {
          if (entry is Map<String, Object?>) {
            all.add(McpToolInfo.fromJson(entry));
          }
        }
        // Schutz vor riesigen Listen: mehr als maxListedTools werden nie
        // angeboten (McpIntegration nimmt ohnehin nur maxToolsPerServer).
        if (all.length >= maxListedTools) {
          _log('MCP: mehr als $maxListedTools Tools, Rest ignoriert');
          return all.sublist(0, maxListedTools);
        }
        final next = result['nextCursor'];
        if (next is! String || next.isEmpty) return all;
        cursor = next;
      }
    }, cancel: cancel);
    final entry = McpToolCache(fetchedAt: clock.now(), tools: tools);
    _cached = entry;
    await cache?.write(config.id, entry);
    return entry.tools;
  }

  /// The cached tool list without contacting the server (`null` if none).
  Future<McpToolCache?> cachedTools() async =>
      _cached ??= await cache?.read(config.id);

  /// Calls the tool [name] (MCP name) with [arguments]. A lost connection
  /// (network error) is retried once with a new session only if
  /// [idempotent]; otherwise the call may already have run on the server
  /// and the error is reported instead. An expired session (HTTP 404) is
  /// always renewed, because the server has not executed that request.
  Future<McpCallResult> callTool(
    String name,
    Map<String, Object?> arguments, {
    CancelToken? cancel,
    bool idempotent = false,
  }) => _run(
    (t) async => McpCallResult.fromResult(
      await t.request('tools/call', {
        'name': name,
        'arguments': arguments,
      }, cancel: cancel),
    ),
    cancel: cancel,
    idempotent: idempotent,
  );

  /// `ping`.
  Future<void> ping({CancelToken? cancel}) =>
      _run((t) => t.request('ping', null, cancel: cancel), cancel: cancel);

  /// Checks reachability with a fresh `initialize` and measures the time.
  Future<McpProbeResult> probe({CancelToken? cancel}) async {
    final watch = Stopwatch()..start();
    try {
      final info = await initialize(cancel: cancel);
      return McpProbeResult(
        status: McpReachability.reachable,
        latency: watch.elapsed,
        server: info,
        transport: transport,
      );
    } on McpException catch (e) {
      return McpProbeResult(
        status: switch (e.kind) {
          McpErrorKind.authRequired => McpReachability.authRequired,
          McpErrorKind.network ||
          McpErrorKind.timeout ||
          McpErrorKind.cancelled ||
          McpErrorKind.rejected => McpReachability.unreachable,
          _ => McpReachability.protocolError,
        },
        latency: watch.elapsed,
        detail: e.message,
      );
    }
  }

  /// Ends the session (`DELETE` for Streamable HTTP). The client stays
  /// usable and reconnects on the next call.
  Future<void> close() async {
    _session = null;
    await _streamable?.close();
  }

  /// Ends the session and closes [toolsChanged].
  Future<void> dispose() async {
    await close();
    await _toolsChanged.close();
  }
}
