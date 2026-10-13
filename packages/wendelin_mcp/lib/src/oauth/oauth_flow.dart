import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../config.dart';
import '../errors.dart';
import '../net_policy.dart';
import '../ports.dart';
import '../transport/http_call.dart';
import 'pkce.dart';

/// Tokens of one server as stored in `McpSecrets` (JSON). Carries what a
/// refresh needs (token endpoint, client, resource), so no new discovery is
/// necessary.
@immutable
final class McpTokenSet {
  /// Creates a token set.
  const McpTokenSet({
    required this.accessToken,
    required this.tokenEndpoint,
    required this.clientId,
    required this.resource,
    this.refreshToken,
    this.expiresAt,
    this.scope,
  });

  /// Decodes [toJson]; throws [FormatException].
  factory McpTokenSet.fromJson(Map<String, Object?> json) {
    String req(String k) => json[k] is String
        ? json[k]! as String
        : throw FormatException('McpTokenSet: $k fehlt');
    String? opt(String k) => json[k] is String ? json[k]! as String : null;
    final expires = opt('expiresAt');
    return McpTokenSet(
      accessToken: req('accessToken'),
      tokenEndpoint: Uri.parse(req('tokenEndpoint')),
      clientId: req('clientId'),
      resource: req('resource'),
      refreshToken: opt('refreshToken'),
      expiresAt: expires == null ? null : DateTime.parse(expires),
      scope: opt('scope'),
    );
  }

  /// Access token (secret).
  final String accessToken;

  /// Refresh token (secret), if issued.
  final String? refreshToken;

  /// Expiry, if the server named one.
  final DateTime? expiresAt;

  /// Granted scopes.
  final String? scope;

  /// Where to refresh.
  final Uri tokenEndpoint;

  /// Client the tokens belong to.
  final String clientId;

  /// Resource indicator (RFC 8707) the tokens are bound to.
  final String resource;

  /// Whether the access token is expired at [now] (30 s margin).
  bool isExpired(DateTime now) =>
      expiresAt != null &&
      !now.isBefore(expiresAt!.subtract(const Duration(seconds: 30)));

  /// JSON form (only for `McpSecrets`).
  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
    if (scope != null) 'scope': scope,
    'tokenEndpoint': tokenEndpoint.toString(),
    'clientId': clientId,
    'resource': resource,
  };

  @override
  String toString() =>
      'McpTokenSet(expiresAt: $expiresAt, refresh: ${refreshToken != null})';
}

/// Authorization server metadata (RFC 8414) as far as the flow needs it.
@immutable
final class AuthServerMetadata {
  /// Creates metadata.
  const AuthServerMetadata({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    this.registrationEndpoint,
  });

  /// Issuer identifier.
  final String issuer;

  /// Authorization endpoint.
  final Uri authorizationEndpoint;

  /// Token endpoint.
  final Uri tokenEndpoint;

  /// Dynamic client registration endpoint (RFC 7591), if offered.
  final Uri? registrationEndpoint;
}

/// Result of the discovery: which authorization server and which scopes.
@immutable
final class OAuthDiscovery {
  /// Creates a discovery result.
  const OAuthDiscovery({
    required this.resource,
    required this.metadata,
    required this.scopes,
  });

  /// Canonical resource URI of the MCP server (RFC 8707).
  final String resource;

  /// Metadata of the authorization server.
  final AuthServerMetadata metadata;

  /// Scopes to request (may be empty).
  final List<String> scopes;
}

/// Parameters of a `WWW-Authenticate: Bearer …` header (lower-case keys).
Map<String, String> parseChallenge(String? header) {
  if (header == null) return const {};
  final out = <String, String>{};
  final re = RegExp(
    r'([A-Za-z_][A-Za-z0-9_\-]*)\s*=\s*("((?:[^"\\]|\\.)*)"|[^\s,]+)',
  );
  for (final m in re.allMatches(header)) {
    final value = m.group(3) ?? m.group(2)!;
    out.putIfAbsent(
      m.group(1)!.toLowerCase(),
      () => value.replaceAllMapped(RegExp(r'\\(.)'), (x) => x.group(1)!),
    );
  }
  return out;
}

/// Canonical resource URI of an MCP server URL (RFC 8707, MCP spec):
/// lower-case scheme and host, no fragment.
String canonicalResource(Uri url) => url
    .replace(scheme: url.scheme.toLowerCase(), host: url.host.toLowerCase())
    .removeFragment()
    .toString();

/// OAuth 2.1 for MCP servers, without a browser of its own:
/// 401 + `WWW-Authenticate` → Protected Resource Metadata (RFC 9728) →
/// Authorization Server Metadata (RFC 8414, OIDC fallback) → dynamic client
/// registration (RFC 7591) if no client id is configured → PKCE S256 +
/// `state` + `resource` (RFC 8707) → token exchange; refresh on expiry.
///
/// Tokens and the registered client are stored only in [secrets].
final class McpOAuthFlow {
  /// Creates the flow. [redirectUri] is the app's callback (e.g.
  /// `app.wendelin://oauth/mcp`); [random] defaults to `Random.secure()`.
  McpOAuthFlow({
    required this.client,
    required this.secrets,
    required this.browser,
    required this.redirectUri,
    this.clock = const SystemClock(),
    Random? random,
    this.clientName = 'Wendelin',
    this.timeouts = const McpTimeouts(),
    this.log,
  }) : _random = random ?? Random.secure();

  /// HTTP client.
  final http.Client client;

  /// Where tokens and client registrations go.
  final McpSecrets secrets;

  /// Shows the authorization page.
  final AuthorizationBrowser browser;

  /// Redirect URI registered for the app.
  final Uri redirectUri;

  /// Time source (token expiry).
  final Clock clock;

  /// Client name for dynamic registration.
  final String clientName;

  /// Limits for metadata and token requests.
  final McpTimeouts timeouts;

  /// Debug log (no secrets).
  final McpLog? log;

  final Random _random;
  final Map<String, Future<McpTokenSet>> _refreshing = {};

  static McpOAuth _oauth(McpServerConfig config) => switch (config.auth) {
    final McpOAuth o => o,
    _ => throw ArgumentError.value(config.id, 'config', 'kein OAuth-Server'),
  };

  /// Runs the whole interactive flow for [config] and stores the tokens.
  /// [challenge] is the `WWW-Authenticate` header of a 401 (if known).
  Future<McpTokenSet> authorize(
    McpServerConfig config, {
    String? challenge,
    CancelToken? cancel,
  }) async {
    final auth = _oauth(config);
    final discovery = await discover(
      config,
      challenge: challenge,
      cancel: cancel,
    );
    final meta = discovery.metadata;
    final (clientId, clientSecret) = await _client(auth, meta, cancel);
    final verifier = randomToken(_random);
    final state = randomToken(_random, 32);
    final url = meta.authorizationEndpoint.replace(
      queryParameters: {
        ...meta.authorizationEndpoint.queryParameters,
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri.toString(),
        'code_challenge': s256Challenge(verifier),
        'code_challenge_method': 'S256',
        'state': state,
        'resource': discovery.resource,
        if (discovery.scopes.isNotEmpty) 'scope': discovery.scopes.join(' '),
      },
    );
    log?.call('MCP-OAuth: Autorisierung bei ${meta.issuer}');
    final Uri back;
    try {
      back = await browser.authorize(url, redirectUri);
    } on Object catch (e) {
      throw McpException(
        McpErrorKind.authRequired,
        'Anmeldung abgebrochen (${e.runtimeType})',
      );
    }
    final code = _checkRedirect(back, state, meta.issuer);
    final tokens = await _tokenRequest(
      meta.tokenEndpoint,
      {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri.toString(),
        'client_id': clientId,
        'code_verifier': verifier,
        'resource': discovery.resource,
        'client_secret': ?clientSecret,
      },
      clientId: clientId,
      resource: discovery.resource,
      cancel: cancel,
    );
    await secrets.write(auth.tokenRef, jsonEncode(tokens.toJson()));
    return tokens;
  }

  String _checkRedirect(Uri back, String state, String issuer) {
    if (back.scheme != redirectUri.scheme ||
        back.host != redirectUri.host ||
        back.path != redirectUri.path) {
      throw const McpException(
        McpErrorKind.rejected,
        'Rückleitung an eine unerwartete Adresse',
      );
    }
    final params = back.queryParameters;
    final error = params['error'];
    if (error != null) {
      throw McpException(
        McpErrorKind.authRequired,
        'Anmeldung abgelehnt: ${excerpt(error, 60)}',
      );
    }
    if (params['state'] != state) {
      throw const McpException(
        McpErrorKind.rejected,
        'Anmeldung verworfen: state stimmt nicht überein',
      );
    }
    final iss = params['iss'];
    if (iss != null && _trimSlash(iss) != _trimSlash(issuer)) {
      throw const McpException(
        McpErrorKind.rejected,
        'Anmeldung verworfen: falscher Aussteller (iss)',
      );
    }
    final code = params['code'];
    if (code == null || code.isEmpty) {
      throw const McpException(McpErrorKind.protocol, 'Kein Code erhalten');
    }
    return code;
  }

  /// Finds the authorization server of [config] (RFC 9728 → RFC 8414).
  Future<OAuthDiscovery> discover(
    McpServerConfig config, {
    String? challenge,
    CancelToken? cancel,
  }) async {
    final auth = _oauth(config);
    final params = parseChallenge(challenge);
    final resource = canonicalResource(config.url);
    final prm = await _protectedResource(config.url, params, cancel);
    final Uri issuer;
    var scopes = <String>[];
    if (prm == null) {
      // Ohne Metadaten (Spezifikation 2025-03-26): Der MCP-Server ist selbst
      // der Autorisierungsserver.
      issuer = _origin(config.url);
    } else {
      final declared = prm['resource'];
      if (declared is! String || !_coversResource(declared, config.url)) {
        throw const McpException(
          McpErrorKind.rejected,
          'Ressourcen-Metadaten gehören zu einem anderen Server',
        );
      }
      final servers = prm['authorization_servers'];
      if (servers is! List<Object?> || servers.firstOrNull is! String) {
        throw const McpException(
          McpErrorKind.protocol,
          'Ressourcen-Metadaten ohne Autorisierungsserver',
        );
      }
      issuer = Uri.parse(servers.first! as String);
      final supported = prm['scopes_supported'];
      if (supported is List<Object?>) {
        scopes = supported.whereType<String>().toList();
      }
    }
    final challengeScope = params['scope'];
    if (challengeScope != null && challengeScope.trim().isNotEmpty) {
      scopes = challengeScope.trim().split(RegExp(r'\s+'));
    } else if (scopes.isEmpty) {
      scopes = auth.scopes;
    }
    checkOAuthUrl(issuer);
    final metadata = await _authServerMetadata(issuer, cancel);
    return OAuthDiscovery(
      resource: resource,
      metadata: metadata,
      scopes: scopes,
    );
  }

  static bool _coversResource(String declared, Uri server) {
    final d = Uri.tryParse(declared);
    if (d == null || !sameOrigin(d, server)) return false;
    final path = _trimSlash(d.path);
    final serverPath = server.path;
    return path.isEmpty ||
        serverPath == path ||
        serverPath.startsWith('$path/') ||
        _trimSlash(serverPath) == path;
  }

  Future<Map<String, Object?>?> _protectedResource(
    Uri server,
    Map<String, String> params,
    CancelToken? cancel,
  ) async {
    final explicit = params['resource_metadata'];
    if (explicit != null) {
      final url = server.resolve(explicit);
      checkOAuthUrl(url);
      final json = await _getJson(url, cancel);
      if (json == null) {
        throw const McpException(
          McpErrorKind.protocol,
          'Ressourcen-Metadaten nicht gefunden',
        );
      }
      return json;
    }
    final path = _trimSlash(server.path);
    for (final candidate in [
      if (path.isNotEmpty) '/.well-known/oauth-protected-resource$path',
      '/.well-known/oauth-protected-resource',
    ]) {
      final url = _origin(server).replace(path: candidate);
      checkOAuthUrl(url);
      final json = await _getJson(url, cancel);
      if (json != null) return json;
    }
    return null;
  }

  Future<AuthServerMetadata> _authServerMetadata(
    Uri issuer,
    CancelToken? cancel,
  ) async {
    final path = _trimSlash(issuer.path);
    final base = _origin(issuer);
    final candidates = [
      '/.well-known/oauth-authorization-server$path',
      '/.well-known/openid-configuration$path',
      if (path.isNotEmpty) '$path/.well-known/openid-configuration',
    ];
    for (final candidate in candidates) {
      final json = await _getJson(base.replace(path: candidate), cancel);
      if (json == null) continue;
      return _parseMetadata(json, issuer);
    }
    throw const McpException(
      McpErrorKind.protocol,
      'Metadaten des Autorisierungsservers nicht gefunden',
    );
  }

  static AuthServerMetadata _parseMetadata(
    Map<String, Object?> json,
    Uri issuer,
  ) {
    Uri endpoint(String key, {bool required = true}) {
      final v = json[key];
      final url = v is String ? Uri.tryParse(v) : null;
      if (url == null) {
        throw McpException(
          McpErrorKind.protocol,
          'Autorisierungsserver: $key fehlt',
        );
      }
      checkOAuthUrl(url);
      return url;
    }

    final declared = json['issuer'];
    if (declared is! String ||
        _trimSlash(declared) != _trimSlash(issuer.toString())) {
      throw const McpException(
        McpErrorKind.rejected,
        'Autorisierungsserver: issuer passt nicht',
      );
    }
    final methods = json['code_challenge_methods_supported'];
    if (methods is! List<Object?> || !methods.contains('S256')) {
      throw const McpException(
        McpErrorKind.protocol,
        'Autorisierungsserver unterstützt kein PKCE (S256)',
      );
    }
    return AuthServerMetadata(
      issuer: declared,
      authorizationEndpoint: endpoint('authorization_endpoint'),
      tokenEndpoint: endpoint('token_endpoint'),
      registrationEndpoint: json['registration_endpoint'] == null
          ? null
          : endpoint('registration_endpoint'),
    );
  }

  /// Client id (and secret) for [meta]: configured, stored from an earlier
  /// registration for the same issuer, or newly registered.
  Future<(String, String?)> _client(
    McpOAuth auth,
    AuthServerMetadata meta,
    CancelToken? cancel,
  ) async {
    final configured = auth.clientId;
    if (configured != null) return (configured, null);
    final stored = await secrets.read(auth.clientRef);
    if (stored != null) {
      try {
        final json = jsonDecode(stored);
        if (json is Map<String, Object?> &&
            json['issuer'] == meta.issuer &&
            json['client_id'] is String) {
          return (
            json['client_id']! as String,
            json['client_secret'] is String
                ? json['client_secret']! as String
                : null,
          );
        }
      } on FormatException {
        // Unlesbar: neu registrieren.
      }
    }
    final endpoint = meta.registrationEndpoint;
    if (endpoint == null) {
      throw const McpException(
        McpErrorKind.authRequired,
        'Server erlaubt keine automatische Registrierung: Client-Id eintragen',
      );
    }
    log?.call('MCP-OAuth: dynamische Registrierung');
    final json = await guarded(cancel, timeouts.response, (abort) async {
      final response = await sendRequest(
        client,
        'POST',
        endpoint,
        headers: {
          'content-type': 'application/json',
          'accept': 'application/json',
        },
        body: jsonEncode({
          'client_name': clientName,
          'redirect_uris': [redirectUri.toString()],
          'grant_types': ['authorization_code', 'refresh_token'],
          'response_types': ['code'],
          'token_endpoint_auth_method': 'none',
        }),
        connect: timeouts.connect,
        abort: abort,
        log: log,
      );
      return _readJson(response);
    });
    final clientId = json['client_id'];
    if (clientId is! String || clientId.isEmpty) {
      throw const McpException(
        McpErrorKind.protocol,
        'Registrierung ohne client_id',
      );
    }
    final secret = json['client_secret'];
    await secrets.write(
      auth.clientRef,
      jsonEncode({
        'issuer': meta.issuer,
        'client_id': clientId,
        if (secret is String) 'client_secret': secret,
      }),
    );
    return (clientId, secret is String ? secret : null);
  }

  /// The stored tokens of [config], or `null`.
  Future<McpTokenSet?> storedTokens(McpServerConfig config) async {
    final raw = await secrets.read(_oauth(config).tokenRef);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, Object?> ? McpTokenSet.fromJson(json) : null;
    } on FormatException {
      return null;
    }
  }

  /// Whether usable tokens exist (valid, or expired but refreshable).
  Future<bool> hasUsableTokens(McpServerConfig config) async {
    final tokens = await storedTokens(config);
    return tokens != null &&
        (!tokens.isExpired(clock.now()) || tokens.refreshToken != null);
  }

  /// A valid access token for [config], refreshed if expired (or if
  /// [forceRefresh], e.g. after a 401). Throws [McpErrorKind.authRequired]
  /// when there is none or it cannot be renewed.
  Future<String> accessToken(
    McpServerConfig config, {
    bool forceRefresh = false,
    CancelToken? cancel,
  }) async {
    final tokens = await storedTokens(config);
    if (tokens == null) {
      throw const McpException(McpErrorKind.authRequired, 'Nicht angemeldet');
    }
    if (!forceRefresh && !tokens.isExpired(clock.now())) {
      return tokens.accessToken;
    }
    return (await refresh(config, cancel: cancel)).accessToken;
  }

  /// Renews the tokens of [config] with the refresh token.
  ///
  /// Single flight per token reference: parallel callers share one refresh
  /// request (servers that rotate refresh tokens would reject the second).
  /// The entry is released when the refresh ends, also after a failure.
  /// Accepted on purpose: the [cancel] token of the *first* caller drives
  /// the shared request, so cancelling it aborts the refresh for every
  /// waiting caller as well.
  Future<McpTokenSet> refresh(McpServerConfig config, {CancelToken? cancel}) {
    final ref = _oauth(config).tokenRef;
    final running = _refreshing[ref];
    if (running != null) return running;
    final run = _refresh(config, cancel).whenComplete(() {
      // Kein Pfeil: remove() gäbe dieses Future zurück, whenComplete würde
      // darauf warten (Verklemmung).
      _refreshing.remove(ref);
    });
    _refreshing[ref] = run;
    return run;
  }

  Future<McpTokenSet> _refresh(
    McpServerConfig config,
    CancelToken? cancel,
  ) async {
    final auth = _oauth(config);
    final tokens = await storedTokens(config);
    final refreshToken = tokens?.refreshToken;
    if (tokens == null || refreshToken == null) {
      throw const McpException(
        McpErrorKind.authRequired,
        'Anmeldung abgelaufen: bitte neu anmelden',
      );
    }
    String? clientSecret;
    final stored = await secrets.read(auth.clientRef);
    if (stored != null) {
      final Object? json;
      try {
        json = jsonDecode(stored);
      } on FormatException {
        throw const McpException(
          McpErrorKind.authRequired,
          'Gespeicherte Client-Daten beschädigt: bitte neu anmelden',
        );
      }
      if (json is Map<String, Object?> &&
          json['client_id'] == tokens.clientId) {
        final secret = json['client_secret'];
        if (secret != null && secret is! String) {
          throw const McpException(
            McpErrorKind.authRequired,
            'Gespeicherte Client-Daten beschädigt: bitte neu anmelden',
          );
        }
        clientSecret = secret as String?;
      }
    }
    log?.call('MCP-OAuth: Token erneuern');
    final McpTokenSet renewed;
    try {
      renewed = await _tokenRequest(
        tokens.tokenEndpoint,
        {
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'client_id': tokens.clientId,
          'resource': tokens.resource,
          'client_secret': ?clientSecret,
        },
        clientId: tokens.clientId,
        resource: tokens.resource,
        previousRefresh: refreshToken,
        cancel: cancel,
      );
    } on McpException catch (e) {
      if (e.statusCode == 400 || e.statusCode == 401) {
        throw const McpException(
          McpErrorKind.authRequired,
          'Anmeldung abgelaufen: bitte neu anmelden',
        );
      }
      rethrow;
    }
    await secrets.write(auth.tokenRef, jsonEncode(renewed.toJson()));
    return renewed;
  }

  /// Forgets the tokens of [config] (the client registration is kept).
  Future<void> signOut(McpServerConfig config) =>
      secrets.delete(_oauth(config).tokenRef);

  Future<McpTokenSet> _tokenRequest(
    Uri endpoint,
    Map<String, String> form, {
    required String clientId,
    required String resource,
    String? previousRefresh,
    CancelToken? cancel,
  }) async {
    checkOAuthUrl(endpoint);
    final json = await guarded(cancel, timeouts.response, (abort) async {
      final response = await sendRequest(
        client,
        'POST',
        endpoint,
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          'accept': 'application/json',
        },
        body: Uri(queryParameters: form).query,
        connect: timeouts.connect,
        abort: abort,
        log: log,
      );
      return _readJson(response, oauthErrors: true);
    });
    final access = json['access_token'];
    final type = json['token_type'];
    if (access is! String ||
        access.isEmpty ||
        type is! String ||
        type.toLowerCase() != 'bearer') {
      throw const McpException(
        McpErrorKind.protocol,
        'Token-Antwort ohne Bearer-Token',
      );
    }
    final expiresIn = json['expires_in'];
    final refresh = json['refresh_token'];
    final scope = json['scope'];
    return McpTokenSet(
      accessToken: access,
      refreshToken: refresh is String ? refresh : previousRefresh,
      expiresAt: expiresIn is num
          ? clock.now().add(Duration(seconds: expiresIn.toInt()))
          : null,
      scope: scope is String ? scope : null,
      tokenEndpoint: endpoint,
      clientId: clientId,
      resource: resource,
    );
  }

  /// GETs a JSON object; `null` for 404 (candidate not present).
  Future<Map<String, Object?>?> _getJson(Uri url, CancelToken? cancel) =>
      guarded(cancel, timeouts.response, (abort) async {
        final response = await sendRequest(
          client,
          'GET',
          url,
          headers: const {'accept': 'application/json'},
          connect: timeouts.connect,
          abort: abort,
          log: log,
        );
        if (response.statusCode == 404 || response.statusCode == 405) {
          unawaited(response.stream.listen(null).cancel());
          return null;
        }
        return _readJson(response);
      });

  Future<Map<String, Object?>> _readJson(
    http.StreamedResponse response, {
    bool oauthErrors = false,
  }) async {
    final body = utf8.decode(
      await readLimited(response.stream, timeouts.maxResponseBytes),
      allowMalformed: true,
    );
    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      if (oauthErrors && (status == 400 || status == 401)) {
        // OAuth-Fehlerantworten nennen nur den Fehlercode, nie Tokens.
        final Object? json;
        try {
          json = jsonDecode(body);
        } on FormatException {
          throw McpException(
            McpErrorKind.server,
            'Token-Anfrage abgelehnt (HTTP $status)',
            statusCode: status,
          );
        }
        final error = json is Map<String, Object?> ? json['error'] : null;
        throw McpException(
          McpErrorKind.server,
          'Token-Anfrage abgelehnt: ${error is String ? excerpt(error, 60) : status}',
          statusCode: status,
        );
      }
      throw httpFailure(status, body);
    }
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const McpException(McpErrorKind.protocol, 'Antwort ist kein JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const McpException(McpErrorKind.protocol, 'JSON-Objekt erwartet');
    }
    return json;
  }
}

Uri _origin(Uri u) => Uri(scheme: u.scheme, host: u.host, port: u.port);

String _trimSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;
