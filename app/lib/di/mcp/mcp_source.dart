import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../integration_decorator.dart';
import '../user_integrations.dart';
import 'mcp_persistence.dart';
import 'mcp_secrets.dart';
import 'mcp_templates.dart';

/// Redirect of the OAuth login: caught by the intent filter of
/// `OAuthRedirectActivity` (Kotlin) and handed back to the waiting
/// [AuthorizationBrowser].
final mcpRedirectUri = Uri.parse('app.wendelin://oauth/mcp');

/// Gets an error of a server that should set its integration to
/// „Fehler“ (e.g. `ToolRegistry.reportError`).
typedef McpErrorSink = void Function(String integrationId, String message);

/// What the „Server hinzufügen“ form produces. Secret values only live here
/// until [McpServerSource.add] writes them to the `SecretStore`.
final class McpDraft {
  /// Creates a draft.
  McpDraft({
    required this.name,
    required this.url,
    this.transport = McpTransportKind.auto,
    this.auth = McpAuthKind.none,
    this.token,
    List<(String, String)> headers = const [],
    this.clientId,
    this.confirmAll = false,
    this.sensitive = false,
  }) : headers = List.unmodifiable(headers);

  /// Display name.
  final String name;

  /// Endpoint.
  final Uri url;

  /// Transport choice.
  final McpTransportKind transport;

  /// Authentication kind.
  final McpAuthKind auth;

  /// Bearer token ([McpAuthKind.bearer]).
  final String? token;

  /// Own headers as (name, secret value) ([McpAuthKind.headers]).
  final List<(String, String)> headers;

  /// Pre-registered OAuth client id; `null` = dynamic registration.
  final String? clientId;

  /// Every tool needs confirmation.
  final bool confirmAll;

  /// Tools only go to providers of the level for sensitive integrations.
  final bool sensitive;

  /// The configuration with secret references of server [id], and the
  /// secrets to store under them.
  (McpServerConfig, Map<String, String>) toConfig(String id, String slug) {
    final secrets = <String, String>{};
    final McpAuth authConfig;
    switch (auth) {
      case McpAuthKind.none:
        authConfig = const McpNoAuth();
      case McpAuthKind.bearer:
        final ref = McpSecretRefs.bearer(id);
        if (token case final t? when t.isNotEmpty) secrets[ref] = t;
        authConfig = McpBearerAuth(ref);
      case McpAuthKind.headers:
        final refs = <String, String>{};
        for (final (i, (name, value)) in headers.indexed) {
          final ref = McpSecretRefs.header(id, i);
          refs[name] = ref;
          if (value.isNotEmpty) secrets[ref] = value;
        }
        authConfig = McpHeadersAuth(refs);
      case McpAuthKind.oauth:
        authConfig = McpOAuth(
          tokenRef: McpSecretRefs.oauthToken(id),
          clientRef: McpSecretRefs.oauthClient(id),
          clientId: (clientId?.trim().isEmpty ?? true)
              ? null
              : clientId!.trim(),
        );
    }
    return (
      McpServerConfig(
        id: id,
        name: name.trim(),
        slug: slug,
        url: url,
        transport: transport,
        auth: authConfig,
        sensitive: sensitive,
        confirmAll: confirmAll,
      ),
      secrets,
    );
  }
}

/// Failure of the OAuth login that the UI shows as a hint.
final class McpSignInException implements Exception {
  /// Creates the failure with a German [message].
  const McpSignInException(this.message);

  /// No browser is installed (AOSP without a browser).
  static const noBrowser = McpSignInException(
    'Kein Browser installiert. Für die Anmeldung wird ein Browser '
    'gebraucht, z. B. Fennec oder Firefox aus F-Droid.',
  );

  /// German text.
  final String message;

  @override
  String toString() => message;
}

/// An MCP server as registered in the `ToolRegistry`: the [McpIntegration]
/// with a snapshot of its tools (the registry copies them, and the sync
/// computes removed tools from the old version), and an availability that
/// never touches the network.
///
/// A new object is created whenever the tools, the configuration or the
/// credentials change (ADR 0012: a new object counts as changed and is
/// registered again, which also clears a reported error).
final class McpServerIntegration extends IntegrationDecorator {
  /// Wraps the MCP integration [inner] as of now.
  McpServerIntegration(McpIntegration super.inner)
    : config = inner.config,
      tools = List.unmodifiable(inner.tools);

  /// The configuration of this version.
  final McpServerConfig config;

  /// The MCP integration.
  McpIntegration get server => inner as McpIntegration;

  @override
  final List<Tool> tools;

  /// Called on every return to the app (`registry.refresh`): answers from
  /// the stored state, without network (WP25 review). Reachability is
  /// checked on activation, „Neu laden“ and with each tool call.
  @override
  Future<Availability> checkAvailability() async => Availability.yes;
}

/// Read-only view of one configured server for the settings screens.
final class McpServerView {
  McpServerView._(this._s);

  final _Server _s;

  /// The configuration.
  McpServerConfig get config => _s.config;

  /// Integration id (`mcp_<slug>`).
  String get integrationId => _s.config.integrationId;

  /// The version currently handed to the registry.
  McpServerIntegration get integration => _s.current;

  /// All tools the server listed (also switched-off ones), as of the cache.
  List<McpToolInfo> get toolInfos => _s.infos;

  /// The offered tools by MCP name.
  Map<String, McpTool> get offered => {
    for (final t in _s.integration.mcpTools) t.mcpName: t,
  };

  /// Tools not offered, with the reason.
  List<McpSkippedTool> get skipped => _s.integration.skippedTools;

  /// Last explicit check, if any.
  McpCheck? get check => _s.check;

  /// Whether the credentials are complete (no network).
  Future<bool> hasCredentials() async =>
      (await _s.integration.setupState()).missingSteps.isEmpty;
}

/// The MCP servers as [UserIntegrationSource] (WP27, ADR 0010/0012).
///
/// - Configuration (without secrets) in the settings ([McpSettings]),
///   secrets in [secrets], tool lists in the settings
///   ([SettingsMcpCacheStore]).
/// - [load] builds one [McpIntegration] per server with the cached tools,
///   without network.
/// - Connections only on demand: [reload] (activation, „Neu laden“),
///   [signIn], tool calls. `list_changed` during a call reloads the list,
///   and the source hands a new version to the registry.
/// - [remove] deletes configuration, cache, check and all secrets of the
///   server at once; [deleteSecrets] is only the follow-up.
final class McpServerSource implements UserIntegrationSource {
  /// Creates the source.
  McpServerSource({
    required this.settings,
    required this.secrets,
    required this.httpClient,
    required this.browser,
    required this.ids,
    this.clock = const SystemClock(),
    this.audit,
    this.reportError,
    this.browserAvailable,
    this.log,
    Uri? redirectUri,
  }) : redirectUri = redirectUri ?? mcpRedirectUri;

  /// Configuration, tool caches and checks.
  final SettingsRepository settings;

  /// Bearer tokens, header values, OAuth tokens.
  final McpSecrets secrets;

  /// HTTP client of the MCP clients.
  final http.Client httpClient;

  /// Shows the OAuth login.
  final AuthorizationBrowser browser;

  /// Server ids.
  final IdGenerator ids;

  /// Time of checks and token expiry.
  final Clock clock;

  /// Audit log for connections and auth failures (no headers, tokens or
  /// OAuth URLs with `code`/`state`).
  final AuditLogRepository? audit;

  /// Sets an integration to „Fehler“ (e.g. token expired).
  final McpErrorSink? reportError;

  /// Whether a browser for the OAuth login is installed.
  final Future<bool> Function()? browserAvailable;

  /// Debug log (the client removes secrets).
  final McpLog? log;

  /// OAuth redirect of the app.
  final Uri redirectUri;

  final Map<String, _Server> _servers = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<void>? _loading;
  bool _disposed = false;

  @override
  UserIntegrationKind get kind => UserIntegrationKind.mcp;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<Integration>> load() async {
    await ready();
    return [for (final s in _servers.values) s.current];
  }

  /// Completes once the stored servers are loaded. A failed load (e.g.
  /// broken settings) is tried again with the next call.
  Future<void> ready() =>
      _loading ??= _loadStored().catchError((Object e, StackTrace st) {
        _loading = null;
        Error.throwWithStackTrace(e, st);
      });

  /// The configured servers, in the order they were added.
  List<McpServerView> get servers => [
    for (final s in _servers.values) McpServerView._(s),
  ];

  /// The server [serverId], or `null`.
  McpServerView? server(String serverId) => switch (_servers[serverId]) {
    null => null,
    final s => McpServerView._(s),
  };

  /// The server with integration id [integrationId], or `null`.
  McpServerView? byIntegrationId(String integrationId) {
    for (final s in _servers.values) {
      if (s.config.integrationId == integrationId) return McpServerView._(s);
    }
    return null;
  }

  /// Checks a server before it is saved, with the secrets of [draft] held
  /// in memory only.
  Future<McpProbeResult> probeDraft(McpDraft draft) async {
    final (config, values) = draft.toConfig('probe', 'probe');
    final client = McpClient(
      config: config,
      httpClient: httpClient,
      secrets: _MemorySecrets(values),
      clock: clock,
      log: log,
    );
    try {
      checkServerUrl(config.url);
      return await client.probe();
    } on McpException catch (e) {
      return McpProbeResult(
        status: McpReachability.unreachable,
        latency: Duration.zero,
        detail: e.message,
      );
    } finally {
      await client.dispose();
    }
  }

  /// Adds the server of [draft]: secrets into [secrets], configuration
  /// into the settings. The switch stays off; the caller enables it. A
  /// first tool list is loaded right away if the server needs no login.
  Future<McpServerView> add(McpDraft draft) async {
    await ready();
    checkServerUrl(draft.url);
    final id = ids.next();
    final slug = McpNaming.slugFor(draft.name, taken: _slugs());
    final (config, values) = draft.toConfig(id, slug);
    for (final MapEntry(:key, :value) in values.entries) {
      await secrets.write(key, value);
    }
    final server = await _build(config);
    _servers[id] = server;
    await _saveConfigs();
    if (config.auth is! McpOAuth) await _check(server);
    _notify();
    return McpServerView._(server);
  }

  /// Replaces the configuration of a server (switches, tool overrides,
  /// name, address). Id, slug and secret references stay.
  Future<void> update(McpServerConfig next) async {
    await ready();
    final old = _servers[next.id];
    if (old == null) throw ArgumentError.value(next.id, 'id', 'unbekannt');
    if (next == old.config) return;
    if (next.url != old.config.url) checkServerUrl(next.url);
    final server = await _build(next, check: old.check);
    _servers[next.id] = server;
    await _saveConfigs();
    await old.dispose();
    _notify();
  }

  /// Stores a new secret [value] under [ref] of server [serverId] (token
  /// replaced, header value entered after an import).
  Future<void> setSecret(String serverId, String ref, String value) async {
    final server = _require(serverId);
    if (!server.config.auth.secretRefs.contains(ref)) {
      throw ArgumentError.value(ref, 'ref', 'gehört nicht zu diesem Server');
    }
    await secrets.write(ref, value);
    await _check(server);
    await _renew(server, force: true);
  }

  /// Connects again: `initialize` and `tools/list`, result stored as the
  /// last check. Runs on activation and with „Neu laden“; never throws.
  Future<McpCheck> reload(String serverId) async {
    final server = _require(serverId);
    final check = await _check(server);
    await _renew(server, force: true);
    return check;
  }

  /// OAuth login in the browser, then [reload]. Throws
  /// [McpSignInException] if no browser is installed and [McpException]
  /// if the login fails.
  Future<McpCheck> signIn(String serverId) async {
    final server = _require(serverId);
    final flow = server.client.oauth;
    if (flow == null) throw StateError('Server ohne OAuth');
    if (!(await browserAvailable?.call() ?? true)) {
      _auditError(
        server.config,
        'mcp_auth',
        McpSignInException.noBrowser.message,
      );
      throw McpSignInException.noBrowser;
    }
    try {
      // The 401 of an unauthenticated request carries the challenge.
      if (server.client.lastChallenge == null) await server.client.probe();
      await flow.authorize(
        server.config,
        challenge: server.client.lastChallenge,
      );
    } on McpException catch (e) {
      _auditError(
        server.config,
        'mcp_auth',
        'Anmeldung fehlgeschlagen: ${e.message}',
      );
      rethrow;
    }
    return reload(serverId);
  }

  /// Forgets the OAuth tokens of [serverId] (the client registration stays).
  Future<void> signOut(String serverId) async {
    final server = _require(serverId);
    await server.client.oauth?.signOut(server.config);
    await server.client.close();
    await _renew(server, force: true);
  }

  /// Deletes the server: configuration, tool cache, check and every secret,
  /// at once.
  Future<void> remove(String serverId) async {
    await ready();
    final server = _servers.remove(serverId);
    if (server == null) return;
    await _saveConfigs();
    await _forget(server.config);
    _notify();
    await server.dispose();
  }

  @override
  Future<void> deleteSecrets(IntegrationRemoval removal) async {
    final integration = removal.integration;
    if (!removal.whole || integration is! McpServerIntegration) return;
    // Only follow-up: never touch a server that is still configured.
    if (_servers.containsKey(integration.config.id)) return;
    await _forget(integration.config);
  }

  /// The server list as JSON for another device: no secrets, references
  /// replaced by a placeholder. [enabled] tells the current switch.
  String exportJson({bool Function(String integrationId)? enabled}) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': exportFormat,
        'version': 1,
        'servers': [
          for (final s in _servers.values)
            {
              ...s.config.toJson()..remove('id'),
              'auth': _placeholderAuth(s.config.auth),
              'enabled': enabled?.call(s.config.integrationId) ?? false,
            },
        ],
      });

  /// Format marker of [exportJson].
  static const exportFormat = 'wendelin.mcp-servers';

  /// Placeholder for a secret in the export.
  static const secretPlaceholder = '<geheim>';

  /// Adds the servers of an [exportJson] file with new ids and secret
  /// references. Secrets are asked for again; servers start switched off.
  /// Throws [FormatException] for a file of another kind.
  Future<List<McpServerView>> importJson(String json) async {
    await ready();
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      throw const FormatException('Keine gültige JSON-Datei');
    }
    if (data is! Map<String, Object?> ||
        data['format'] != exportFormat ||
        data['servers'] is! List) {
      throw const FormatException('Keine Serverliste von Wendelin');
    }
    final parsed = <McpServerConfig>[];
    for (final entry in data['servers']! as List) {
      if (entry is! Map<String, Object?>) {
        throw const FormatException('Eintrag ist kein Objekt');
      }
      parsed.add(McpServerConfig.fromJson({...entry, 'id': 'import'}));
    }
    final added = <McpServerView>[];
    for (final imported in parsed) {
      checkServerUrl(imported.url);
      final id = ids.next();
      final taken = _slugs();
      final slug = taken.contains(imported.slug) || imported.slug.isEmpty
          ? McpNaming.slugFor(imported.name, taken: taken)
          : imported.slug;
      final config = McpServerConfig(
        id: id,
        name: imported.name,
        slug: slug,
        url: imported.url,
        transport: imported.transport,
        auth: _freshAuth(id, imported.auth),
        sensitive: imported.sensitive,
        confirmAll: imported.confirmAll,
        toolOverrides: imported.toolOverrides,
      );
      final server = await _build(config);
      _servers[id] = server;
      added.add(McpServerView._(server));
    }
    await _saveConfigs();
    _notify();
    return added;
  }

  /// Stops all clients.
  Future<void> dispose() async {
    _disposed = true;
    for (final s in _servers.values) {
      await s.dispose();
    }
    await _changes.close();
  }

  // --- internals ---

  Future<void> _loadStored() async {
    final configs = await settings.get(McpSettings.servers) ?? const [];
    for (final config in configs) {
      if (_servers.containsKey(config.id)) continue;
      _servers[config.id] = await _build(
        config,
        check: await _readCheck(config.id),
      );
    }
  }

  Future<McpCheck?> _readCheck(String id) async {
    try {
      return await settings.get(McpSettings.check(id));
    } on FormatException {
      return null;
    }
  }

  Future<_Server> _build(McpServerConfig config, {McpCheck? check}) async {
    final oauth = config.auth is McpOAuth
        ? McpOAuthFlow(
            client: httpClient,
            secrets: secrets,
            browser: browser,
            redirectUri: redirectUri,
            clock: clock,
            log: log,
          )
        : null;
    final client = McpClient(
      config: config,
      httpClient: httpClient,
      secrets: secrets,
      oauth: oauth,
      cache: SettingsMcpCacheStore(settings),
      clock: clock,
      log: log,
    );
    final integration = McpIntegration(client: client, reportError: _onError);
    await integration.loadCachedTools();
    final server = _Server(config, client, integration)
      ..check = check
      ..infos = (await client.cachedTools())?.tools ?? const [];
    server.wrap();
    server.subscription = integration.toolsChanged.listen(
      (_) => unawaited(_renew(server)),
    );
    return server;
  }

  /// Probes [server], loads its tools if reachable and stores the result.
  Future<McpCheck> _check(_Server server) async {
    final probe = await server.client.probe();
    var check = McpCheck.fromProbe(probe, clock.now());
    if (check.ok) {
      try {
        await server.integration.loadTools(refresh: true);
      } on McpException catch (e) {
        check = McpCheck(
          at: check.at,
          status: e.kind == McpErrorKind.authRequired
              ? McpReachability.authRequired
              : McpReachability.protocolError,
          detail: e.message,
          latency: check.latency,
          serverName: check.serverName,
          transport: check.transport,
        );
      }
    }
    server
      ..check = check
      ..infos = (await server.client.cachedTools())?.tools ?? server.infos;
    try {
      await settings.set(McpSettings.check(server.config.id), check);
    } on Object catch (e) {
      log?.call('MCP: Prüfergebnis nicht gespeichert: ${e.runtimeType}');
    }
    _auditCheck(server.config, check);
    if (check.status == McpReachability.authRequired &&
        server.config.auth is! McpNoAuth) {
      _onError(
        server.config.integrationId,
        'Anmeldung nötig${check.detail == null ? '' : ': ${check.detail}'}',
      );
    }
    return check;
  }

  /// Hands a new version of [server] to the registry if its tools changed
  /// (or always with [force], e.g. to clear a reported error).
  Future<void> _renew(_Server server, {bool force = false}) async {
    if (_disposed || !identical(_servers[server.config.id], server)) return;
    if (!force && identical(server.wrappedTools, server.integration.tools)) {
      return;
    }
    server.wrap();
    final cache = await server.client.cachedTools();
    if (cache != null) server.infos = cache.tools;
    _notify();
  }

  void _onError(String integrationId, String message) {
    final server = _servers.values
        .where((s) => s.config.integrationId == integrationId)
        .firstOrNull;
    if (server != null) _auditError(server.config, 'mcp_auth', message);
    reportError?.call(integrationId, message);
  }

  Future<void> _forget(McpServerConfig config) async {
    Future<void> guard(Future<void> Function() step) async {
      try {
        await step();
      } on Object catch (e) {
        log?.call('MCP: Aufräumen unvollständig: ${e.runtimeType}');
      }
    }

    for (final ref in config.auth.secretRefs) {
      await guard(() => secrets.delete(ref));
    }
    await guard(() => settings.remove(McpSettings.cache(config.id)));
    await guard(() => settings.remove(McpSettings.check(config.id)));
  }

  Future<void> _saveConfigs() => settings.set(McpSettings.servers, [
    for (final s in _servers.values) s.config,
  ]);

  Set<String> _slugs() => {for (final s in _servers.values) s.config.slug};

  _Server _require(String serverId) =>
      _servers[serverId] ??
      (throw ArgumentError.value(serverId, 'serverId', 'unbekannt'));

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _auditCheck(McpServerConfig config, McpCheck check) => _record(
    AuditEntry(
      at: clock.now(),
      kind: check.ok ? AuditKind.verification : AuditKind.error,
      payload: {
        'source': 'mcp',
        'profileId': config.integrationId,
        'server': config.name,
        'status': check.status.name,
        'latencyMs': ?check.latency?.inMilliseconds,
        if (!check.ok)
          'message':
              'MCP-Server „${config.name}“: '
              '${sanitizeMcpDetail(check.detail ?? check.status.name)}',
      },
    ),
  );

  void _auditError(McpServerConfig config, String error, String message) =>
      _record(
        AuditEntry(
          at: clock.now(),
          kind: AuditKind.error,
          payload: {
            'source': 'mcp',
            'error': error,
            'server': config.name,
            'message':
                'MCP-Server „${config.name}“: ${sanitizeMcpDetail(message)}',
          },
        ),
      );

  void _record(AuditEntry entry) {
    final repository = audit;
    if (repository == null) return;
    unawaited(
      repository
          .record(entry)
          .then<void>(
            (_) {},
            onError: (Object e) => log?.call(
              'MCP: Audit-Eintrag nicht geschrieben: ${e.runtimeType}',
            ),
          ),
    );
  }

  static Map<String, Object?> _placeholderAuth(McpAuth auth) => switch (auth) {
    McpNoAuth() => auth.toJson(),
    McpBearerAuth() => {
      'kind': McpBearerAuth.jsonKind,
      'secretRef': secretPlaceholder,
    },
    McpHeadersAuth(:final secretRefsByHeader) => {
      'kind': McpHeadersAuth.jsonKind,
      'secretRefs': {
        for (final h in secretRefsByHeader.keys) h: secretPlaceholder,
      },
    },
    McpOAuth(:final clientId, :final scopes) => {
      'kind': McpOAuth.jsonKind,
      'tokenRef': secretPlaceholder,
      'clientRef': secretPlaceholder,
      'clientId': ?clientId,
      if (scopes.isNotEmpty) 'scopes': scopes,
    },
  };

  static McpAuth _freshAuth(String id, McpAuth auth) => switch (auth) {
    McpNoAuth() => auth,
    McpBearerAuth() => McpBearerAuth(McpSecretRefs.bearer(id)),
    McpHeadersAuth(:final secretRefsByHeader) => McpHeadersAuth({
      for (final (i, h) in secretRefsByHeader.keys.indexed)
        h: McpSecretRefs.header(id, i),
    }),
    McpOAuth(:final clientId, :final scopes) => McpOAuth(
      tokenRef: McpSecretRefs.oauthToken(id),
      clientRef: McpSecretRefs.oauthClient(id),
      clientId: clientId,
      scopes: scopes,
    ),
  };
}

/// [detail] for logs and the audit log: addresses without query and
/// fragment (an OAuth redirect carries `code` and `state`).
String sanitizeMcpDetail(String detail) => detail.replaceAllMapped(
  RegExp(r'([a-zA-Z][a-zA-Z0-9+.-]*://[^\s?#]+)[?#][^\s]*'),
  (m) => '${m[1]}?…',
);

/// Mutable state of one configured server.
final class _Server {
  _Server(this.config, this.client, this.integration);

  final McpServerConfig config;
  final McpClient client;
  final McpIntegration integration;
  late McpServerIntegration current;
  List<Tool> wrappedTools = const [];
  List<McpToolInfo> infos = const [];
  McpCheck? check;
  StreamSubscription<void>? subscription;

  /// A new registry version of the current tools.
  void wrap() {
    wrappedTools = integration.tools;
    current = McpServerIntegration(integration);
  }

  Future<void> dispose() async {
    await subscription?.cancel();
    await integration.dispose();
    await client.dispose();
  }
}

/// Secrets of a draft, only in memory (probe before saving).
final class _MemorySecrets implements McpSecrets {
  _MemorySecrets(this._values);

  final Map<String, String> _values;

  @override
  Future<String?> read(String ref) async => _values[ref];

  @override
  Future<void> write(String ref, String value) async => _values[ref] = value;

  @override
  Future<void> delete(String ref) async => _values.remove(ref);
}
