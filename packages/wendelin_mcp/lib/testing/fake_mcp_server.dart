import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../src/oauth/pkce.dart';

/// Transport the [FakeMcpServer] speaks.
enum FakeTransportMode {
  /// Streamable HTTP: `POST /mcp`, answers as JSON or SSE.
  streamable,

  /// Legacy-SSE: `GET /mcp` opens the stream, `POST /messages?sessionId=`.
  legacySse,
}

/// How Streamable HTTP answers requests.
enum FakeResponseStyle {
  /// `application/json` (notifications before the answer are dropped).
  json,

  /// `text/event-stream` (notifications and server requests first).
  sse,
}

/// Authentication the server requires on the MCP endpoint.
enum FakeAuthMode {
  /// None.
  none,

  /// `Authorization: Bearer <bearerToken>`.
  bearer,

  /// OAuth 2.1 with the built-in authorization server under `/as`.
  oauth,
}

/// Handler of a scripted tool: returns the `tools/call` result object.
typedef FakeToolHandler = FutureOr<Map<String, Object?>> Function(
  Map<String, Object?> args,
);

/// A scripted tool of the [FakeMcpServer].
final class FakeMcpTool {
  /// Creates a tool; without [handler] it answers with the text `ok`.
  FakeMcpTool(
    this.name, {
    this.description = '',
    this.inputSchema = const {'type': 'object'},
    this.annotations,
    this.handler,
  });

  /// MCP name.
  final String name;

  /// Description.
  final String description;

  /// Input schema.
  final Map<String, Object?> inputSchema;

  /// Annotations (`readOnlyHint`, …).
  final Map<String, Object?>? annotations;

  /// Result producer.
  final FakeToolHandler? handler;

  /// `tools/list` entry.
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': ?annotations,
  };
}

/// A request the server received.
final class FakeMcpRequest {
  /// Creates a record.
  FakeMcpRequest(this.method, this.uri, this.headers, this.body);

  /// HTTP method.
  final String method;

  /// Path and query.
  final Uri uri;

  /// Headers (lower-case names, first value).
  final Map<String, String> headers;

  /// Body text.
  final String body;

  /// JSON-RPC method of the body, if any.
  String? get rpcMethod {
    try {
      final json = jsonDecode(body);
      return json is Map<String, Object?> ? json['method'] as String? : null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => '$method ${uri.path} ${rpcMethod ?? ''}';
}

/// In-process MCP server on `127.0.0.1` (`dart:io` [HttpServer]) for tests
/// and as test server for the emulator (WP29).
///
/// Switchable between Streamable HTTP and Legacy-SSE, JSON or SSE answers,
/// bearer or OAuth (protected resource metadata, authorization server
/// metadata, dynamic client registration, PKCE-checking authorize and
/// token endpoints, refresh); scriptable tools, pagination,
/// `list_changed`, server requests, errors, delays, oversized answers and
/// session expiry (404).
final class FakeMcpServer {
  FakeMcpServer._(this._server, {String host = '127.0.0.1'})
    : origin = Uri(scheme: 'http', host: host, port: _server.port);

  /// Starts the server on a free port of [address] (loopback by default;
  /// `InternetAddress.anyIPv4` for an emulator, with [publicHost] `10.0.2.2`
  /// so the metadata URLs point where the emulator reaches the host).
  static Future<FakeMcpServer> start({
    InternetAddress? address,
    String publicHost = '127.0.0.1',
    FakeTransportMode mode = FakeTransportMode.streamable,
    FakeResponseStyle style = FakeResponseStyle.json,
    FakeAuthMode auth = FakeAuthMode.none,
    List<FakeMcpTool> tools = const [],
  }) async {
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      0,
    );
    final fake = FakeMcpServer._(server, host: publicHost)
      ..mode = mode
      ..style = style
      ..auth = auth
      ..tools = List.of(tools);
    server.listen(fake._handle);
    return fake;
  }

  final HttpServer _server;

  /// `http://127.0.0.1:<port>`.
  final Uri origin;

  /// The MCP endpoint (both modes).
  Uri get url => origin.replace(path: '/mcp');

  /// Issuer of the built-in authorization server.
  Uri get issuer => origin.replace(path: '/as');

  // --- Einstellungen -------------------------------------------------------

  /// Transport.
  FakeTransportMode mode = FakeTransportMode.streamable;

  /// Answer style for Streamable HTTP.
  FakeResponseStyle style = FakeResponseStyle.json;

  /// Required authentication.
  FakeAuthMode auth = FakeAuthMode.none;

  /// Token for [FakeAuthMode.bearer].
  String bearerToken = 'fake-bearer-token';

  /// Tools.
  List<FakeMcpTool> tools = [];

  /// Tools per `tools/list` page (`null` = all at once).
  int? pageSize;

  /// Protocol version answered in `initialize` (`null` = the client's).
  String? protocolVersion;

  /// `initialize` result replacing the generated one (fixtures).
  Map<String, Object?>? initializeResult;

  /// Waits this long before answering a request.
  Duration delay = Duration.zero;

  /// Never answers requests (until [close]).
  bool hang = false;

  /// Sends `notifications/tools/list_changed` (and a log message) before
  /// each `tools/call` answer (SSE answers and Legacy-SSE only).
  bool sendListChanged = false;

  /// Sends a server request (`sampling/createMessage` and `ping`) before
  /// each `tools/call` answer (SSE answers and Legacy-SSE only).
  bool sendServerRequests = false;

  /// Adds this many bytes of padding to every answer.
  int padding = 0;

  /// The next MCP `POST`s answer with this status instead.
  final List<int> failNext = [];

  /// Status a Legacy-SSE server answers a `POST` to `/mcp` with (405, 404
  /// or 400 are all seen in the wild).
  int legacyPostStatus = 405;

  /// Endpoint announced by Legacy-SSE (`null` = own `/messages`).
  String? legacyEndpoint;

  // OAuth
  /// Serves protected resource metadata (RFC 9728); otherwise the server
  /// is its own authorization server (at the origin).
  bool withResourceMetadata = true;

  /// Serves metadata only at the OpenID Connect location.
  bool oidcOnly = false;

  /// `issuer` announced in the metadata (`null` = the real one; set it to
  /// simulate a mix-up attack).
  String? metadataIssuer;

  /// Offers dynamic client registration.
  bool dynamicRegistration = true;

  /// Announces `S256` in `code_challenge_methods_supported`.
  bool announceS256 = true;

  /// `expires_in` of issued access tokens.
  int tokenLifetimeSeconds = 3600;

  /// Refuses refresh requests (`invalid_grant`).
  bool rejectRefresh = false;

  /// Issues refresh tokens.
  bool issueRefreshTokens = true;

  // --- Aufzeichnung --------------------------------------------------------

  /// Every request.
  final List<FakeMcpRequest> requests = [];

  /// Answers the client sent to server requests.
  final List<Map<String, Object?>> clientAnswers = [];

  /// Notifications the client sent.
  final List<String> clientNotifications = [];

  /// Live session ids (Streamable HTTP and Legacy-SSE).
  final Set<String> sessions = {};

  /// `DELETE` requests received.
  int deletes = 0;

  /// Registered clients (client id → registration body).
  final Map<String, Map<String, Object?>> registrations = {};

  /// Query parameters of the last authorization request.
  Map<String, String>? lastAuthorization;

  /// Form fields of all token requests.
  final List<Map<String, String>> tokenRequests = [];

  /// Valid access tokens.
  final Set<String> accessTokens = {};

  /// Valid refresh tokens.
  final Set<String> refreshTokens = {};

  final Map<String, _Grant> _codes = {};
  final Map<String, _LegacySession> _legacy = {};
  var _counter = 0;
  final List<Completer<void>> _hanging = [];

  /// Forgets all sessions (next request with an old id gets 404).
  void expireSessions() => sessions.clear();

  /// Invalidates all access tokens (next request gets 401).
  void expireAccessTokens() => accessTokens.clear();

  /// Stops the server and drops open connections.
  Future<void> close() async {
    for (final c in _hanging) {
      if (!c.isCompleted) c.complete();
    }
    for (final s in _legacy.values.toList()) {
      await s.close();
    }
    await _server.close(force: true);
  }

  String _id(String prefix) => '$prefix-${++_counter}';

  Future<void> _handle(HttpRequest req) async {
    final body = await utf8.decoder.bind(req).join();
    final headers = <String, String>{};
    req.headers.forEach((name, values) => headers[name] = values.first);
    requests.add(FakeMcpRequest(req.method, req.uri, headers, body));
    final res = req.response;
    try {
      final path = req.uri.path;
      if (path == '/mcp') {
        await _mcp(req, body, headers);
      } else if (path == '/messages') {
        await _legacyPost(req, body);
      } else if (path.startsWith('/.well-known/') || path.startsWith('/as')) {
        await _oauth(req, body);
      } else {
        await _send(res, 404, 'not found');
      }
    } on Object catch (e) {
      try {
        await _send(res, 500, 'fake server error: $e');
      } on Object {
        // Verbindung bereits geschlossen.
      }
    }
  }

  Future<void> _send(
    HttpResponse res,
    int status,
    String body, {
    String type = 'text/plain',
    Map<String, String> headers = const {},
  }) async {
    res.statusCode = status;
    res.headers.contentType = ContentType.parse('$type; charset=utf-8');
    headers.forEach(res.headers.set);
    res.write(body);
    await res.close();
  }

  Future<void> _json(
    HttpResponse res,
    Object? json, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => _send(
    res,
    status,
    jsonEncode(json),
    type: 'application/json',
    headers: headers,
  );

  bool _authorized(Map<String, String> headers) {
    final header = headers['authorization'] ?? '';
    return switch (auth) {
      FakeAuthMode.none => true,
      FakeAuthMode.bearer => header == 'Bearer $bearerToken',
      FakeAuthMode.oauth =>
        header.startsWith('Bearer ') &&
            accessTokens.contains(header.substring(7)),
    };
  }

  Future<void> _unauthorized(HttpResponse res) {
    final challenge = auth == FakeAuthMode.oauth && withResourceMetadata
        ? 'Bearer resource_metadata="'
              '${origin.replace(path: '/.well-known/oauth-protected-resource/mcp')}", '
              'scope="mcp:tools"'
        : 'Bearer realm="fake"';
    return _send(
      res,
      401,
      'unauthorized',
      headers: {'www-authenticate': challenge},
    );
  }

  // --- MCP-Endpunkt ---------------------------------------------------------

  Future<void> _mcp(
    HttpRequest req,
    String body,
    Map<String, String> headers,
  ) async {
    final res = req.response;
    if (!_authorized(headers)) return _unauthorized(res);
    if (mode == FakeTransportMode.legacySse) {
      if (req.method == 'GET') return _legacyOpen(res);
      return _send(res, legacyPostStatus, 'method not allowed');
    }
    if (req.method == 'DELETE') {
      deletes++;
      sessions.remove(headers['mcp-session-id']);
      return _send(res, 200, '');
    }
    if (req.method != 'POST') return _send(res, 405, 'method not allowed');
    if (failNext.isNotEmpty) {
      return _send(res, failNext.removeAt(0), 'scripted failure');
    }
    final message = jsonDecode(body) as Map<String, Object?>;
    final method = message['method'] as String?;
    final id = message['id'];
    final session = headers['mcp-session-id'];
    var newSession = <String, String>{};
    if (method == 'initialize') {
      final sid = _id('session');
      sessions.add(sid);
      newSession = {'mcp-session-id': sid};
    } else if (session == null) {
      return _send(res, 400, 'missing session');
    } else if (!sessions.contains(session)) {
      return _send(res, 404, 'unknown session');
    }
    if (method == null) {
      clientAnswers.add(message);
      return _send(res, 202, '');
    }
    if (id == null) {
      clientNotifications.add(method);
      return _send(res, 202, '');
    }
    await _wait();
    final pre = _preMessages(method);
    final answer = await _answer(id, method, message['params']);
    if (style == FakeResponseStyle.json) {
      return _json(res, answer, headers: newSession);
    }
    res.statusCode = 200;
    res.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    newSession.forEach(res.headers.set);
    for (final m in [...pre, answer]) {
      res.write('event: message\ndata: ${jsonEncode(m)}\n\n');
      await res.flush();
    }
    await res.close();
  }

  Future<void> _wait() async {
    if (hang) {
      final c = Completer<void>();
      _hanging.add(c);
      await c.future;
    }
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  List<Map<String, Object?>> _preMessages(String method) => [
    if (method == 'tools/call' && sendListChanged) ...[
      {
        'jsonrpc': '2.0',
        'method': 'notifications/message',
        'params': {'level': 'info', 'data': 'Tool läuft'},
      },
      {'jsonrpc': '2.0', 'method': 'notifications/tools/list_changed'},
    ],
    if (method == 'tools/call' && sendServerRequests) ...[
      {
        'jsonrpc': '2.0',
        'id': _id('srv'),
        'method': 'sampling/createMessage',
        'params': {'messages': <Object?>[], 'maxTokens': 10},
      },
      {'jsonrpc': '2.0', 'id': _id('srv'), 'method': 'ping'},
    ],
  ];

  Future<Map<String, Object?>> _answer(
    Object id,
    String method,
    Object? params,
  ) async {
    final p = params is Map<String, Object?>
        ? params
        : const <String, Object?>{};
    Map<String, Object?> result(Object? r) => {
      'jsonrpc': '2.0',
      'id': id,
      'result': r,
      if (padding > 0) '_padding': 'x' * padding,
    };
    Map<String, Object?> error(int code, String message) => {
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    };
    switch (method) {
      case 'initialize':
        return result(
          initializeResult ??
              {
                'protocolVersion':
                    protocolVersion ?? p['protocolVersion'] ?? '2025-06-18',
                'capabilities': {
                  'tools': {'listChanged': true},
                },
                'serverInfo': {'name': 'fake-mcp', 'version': '1.0.0'},
              },
        );
      case 'ping':
        return result(const <String, Object?>{});
      case 'tools/list':
        final start = int.tryParse('${p['cursor'] ?? 0}') ?? 0;
        final size = pageSize ?? tools.length;
        final end = (start + size).clamp(0, tools.length);
        return result({
          'tools': [for (final t in tools.sublist(start, end)) t.toJson()],
          if (end < tools.length) 'nextCursor': '$end',
        });
      case 'tools/call':
        final name = p['name'];
        final tool = tools.where((t) => t.name == name).firstOrNull;
        if (tool == null) return error(-32602, 'Unknown tool: $name');
        final args = p['arguments'];
        try {
          final handler = tool.handler;
          return result(
            handler == null
                ? {
                    'content': [
                      {'type': 'text', 'text': 'ok'},
                    ],
                  }
                : await handler(args is Map<String, Object?> ? args : const {}),
          );
        } on Object catch (e) {
          return error(-32603, 'Tool failed: $e');
        }
      default:
        return error(-32601, 'Method not found: $method');
    }
  }

  // --- Legacy-SSE -----------------------------------------------------------

  Future<void> _legacyOpen(HttpResponse res) async {
    final sid = _id('legacy');
    sessions.add(sid);
    res.statusCode = 200;
    res.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    res.bufferOutput = false;
    final session = _LegacySession(res);
    _legacy[sid] = session;
    session.event('endpoint', legacyEndpoint ?? '/messages?sessionId=$sid');
    await session.done.future;
    _legacy.remove(sid);
    sessions.remove(sid);
  }

  Future<void> _legacyPost(HttpRequest req, String body) async {
    final res = req.response;
    final headers = <String, String>{};
    req.headers.forEach((name, values) => headers[name] = values.first);
    if (!_authorized(headers)) return _unauthorized(res);
    final sid = req.uri.queryParameters['sessionId'];
    final session = _legacy[sid];
    if (session == null) return _send(res, 404, 'unknown session');
    if (failNext.isNotEmpty) {
      return _send(res, failNext.removeAt(0), 'scripted failure');
    }
    final message = jsonDecode(body) as Map<String, Object?>;
    final method = message['method'] as String?;
    final id = message['id'];
    await _send(res, 202, 'Accepted');
    if (method == null) {
      clientAnswers.add(message);
      return;
    }
    if (id == null) {
      clientNotifications.add(method);
      return;
    }
    await _wait();
    for (final m in _preMessages(method)) {
      session.event('message', jsonEncode(m));
    }
    session.event(
      'message',
      jsonEncode(await _answer(id, method, message['params'])),
    );
  }

  // --- OAuth ----------------------------------------------------------------

  Map<String, Object?> get _asMetadata => {
    'issuer':
        metadataIssuer ?? (withResourceMetadata ? issuer : origin).toString(),
    'authorization_endpoint': origin.replace(path: '/as/authorize').toString(),
    'token_endpoint': origin.replace(path: '/as/token').toString(),
    if (dynamicRegistration)
      'registration_endpoint': origin.replace(path: '/as/register').toString(),
    'response_types_supported': ['code'],
    if (announceS256) 'code_challenge_methods_supported': ['S256'],
  };

  Future<void> _oauth(HttpRequest req, String body) async {
    final res = req.response;
    final path = req.uri.path;
    final asPath = withResourceMetadata ? '/as' : '';
    if (auth != FakeAuthMode.oauth) return _send(res, 404, 'no oauth');
    if (path == '/.well-known/oauth-protected-resource/mcp' &&
        withResourceMetadata) {
      return _json(res, {
        'resource': url.toString(),
        'authorization_servers': [issuer.toString()],
        'scopes_supported': ['mcp:tools'],
      });
    }
    if ((!oidcOnly &&
            path == '/.well-known/oauth-authorization-server$asPath') ||
        (oidcOnly && path == '/.well-known/openid-configuration$asPath')) {
      return _json(res, _asMetadata);
    }
    switch (path) {
      case '/as/register' when dynamicRegistration && req.method == 'POST':
        final clientId = _id('client');
        registrations[clientId] = jsonDecode(body) as Map<String, Object?>;
        return _json(res, {'client_id': clientId}, status: 201);
      case '/as/authorize':
        final q = req.uri.queryParameters;
        lastAuthorization = q;
        final redirect = Uri.parse(q['redirect_uri'] ?? '');
        if (q['response_type'] != 'code' ||
            q['code_challenge_method'] != 'S256' ||
            q['code_challenge'] == null) {
          return _send(res, 400, 'bad authorization request');
        }
        final code = _id('code');
        _codes[code] = _Grant(
          clientId: q['client_id'] ?? '',
          challenge: q['code_challenge']!,
          redirect: q['redirect_uri'] ?? '',
          resource: q['resource'],
        );
        final back = redirect.replace(
          queryParameters: {
            ...redirect.queryParameters,
            'code': code,
            if (q['state'] != null) 'state': q['state']!,
            'iss': _asMetadata['issuer']! as String,
          },
        );
        return _send(res, 302, '', headers: {'location': back.toString()});
      case '/as/token' when req.method == 'POST':
        final form = Uri.splitQueryString(body);
        tokenRequests.add(form);
        return _token(res, form);
    }
    return _send(res, 404, 'not found');
  }

  Future<void> _token(HttpResponse res, Map<String, String> form) {
    Future<void> invalid(String error) =>
        _json(res, {'error': error}, status: 400);
    switch (form['grant_type']) {
      case 'authorization_code':
        final grant = _codes.remove(form['code']);
        if (grant == null) return invalid('invalid_grant');
        final verifier = form['code_verifier'] ?? '';
        if (s256Challenge(verifier) != grant.challenge ||
            grant.clientId != form['client_id'] ||
            grant.redirect != form['redirect_uri'] ||
            grant.resource != form['resource']) {
          return invalid('invalid_grant');
        }
        return _issue(res);
      case 'refresh_token':
        final token = form['refresh_token'];
        if (rejectRefresh || !refreshTokens.remove(token)) {
          return invalid('invalid_grant');
        }
        return _issue(res);
      default:
        return invalid('unsupported_grant_type');
    }
  }

  Future<void> _issue(HttpResponse res) {
    final access = _id('access-token-value');
    accessTokens.add(access);
    final refresh = issueRefreshTokens ? _id('refresh-token-value') : null;
    if (refresh != null) refreshTokens.add(refresh);
    return _json(res, {
      'access_token': access,
      'token_type': 'Bearer',
      'expires_in': tokenLifetimeSeconds,
      'refresh_token': ?refresh,
      'scope': 'mcp:tools',
    });
  }
}

final class _Grant {
  _Grant({
    required this.clientId,
    required this.challenge,
    required this.redirect,
    required this.resource,
  });

  final String clientId;
  final String challenge;
  final String redirect;
  final String? resource;
}

final class _LegacySession {
  _LegacySession(this.res) {
    unawaited(res.done.then((_) => close(), onError: (Object _) => close()));
    // Kommentarzeilen als Keep-alive; scheitert das Schreiben, hat der
    // Client die Verbindung getrennt.
    _keepAlive = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (done.isCompleted) return;
      try {
        res.write(':\n\n');
        res.flush().catchError((Object _) => close());
      } on Object {
        unawaited(close());
      }
    });
  }

  final HttpResponse res;
  final Completer<void> done = Completer<void>();
  late final Timer _keepAlive;

  void event(String name, String data) {
    if (done.isCompleted) return;
    res.write('event: $name\ndata: $data\n\n');
  }

  Future<void> close() async {
    if (done.isCompleted) return;
    done.complete();
    _keepAlive.cancel();
    try {
      await res.close();
    } on Object {
      // Client hat die Verbindung schon getrennt.
    }
  }
}
