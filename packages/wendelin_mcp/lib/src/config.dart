import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// How the client talks to the server.
enum McpTransportKind {
  /// Streamable HTTP first, Legacy-SSE if the server refuses `POST`.
  auto,

  /// Streamable HTTP (MCP 2025-06-18 and newer).
  streamable,

  /// Legacy HTTP+SSE (MCP 2024-11-05).
  sse,
}

/// How the client authenticates. Holds only *references* to secrets in
/// `McpSecrets`, never the secrets themselves.
@immutable
sealed class McpAuth {
  const McpAuth();

  /// Decodes an auth written by [toJson]; throws [FormatException].
  factory McpAuth.fromJson(Map<String, Object?> json) {
    final kind = _read<String>(json, 'kind');
    return switch (kind) {
      McpNoAuth.jsonKind => const McpNoAuth(),
      McpBearerAuth.jsonKind => McpBearerAuth(_read(json, 'secretRef')),
      McpHeadersAuth.jsonKind => McpHeadersAuth({
        for (final MapEntry(:key, :value) in _read<Map<String, Object?>>(
          json,
          'secretRefs',
        ).entries)
          key: value is String
              ? value
              : throw const FormatException('McpHeadersAuth: Referenz'),
      }),
      McpOAuth.jsonKind => McpOAuth(
        tokenRef: _read(json, 'tokenRef'),
        clientRef: _read(json, 'clientRef'),
        clientId: _opt(json, 'clientId'),
        scopes: [
          for (final s in _opt<List<Object?>>(json, 'scopes') ?? const [])
            s is String ? s : throw const FormatException('McpOAuth: scopes'),
        ],
      ),
      _ => throw FormatException('McpAuth: unbekannte Art "$kind"'),
    };
  }

  /// JSON without secrets.
  Map<String, Object?> toJson();

  /// All secret references this auth uses.
  Set<String> get secretRefs;
}

/// No authentication (e.g. a server only reachable over Tailscale).
final class McpNoAuth extends McpAuth {
  /// Creates no-auth.
  const McpNoAuth();

  /// JSON discriminator.
  static const jsonKind = 'none';

  @override
  Set<String> get secretRefs => const {};

  @override
  Map<String, Object?> toJson() => {'kind': jsonKind};

  @override
  bool operator ==(Object other) => other is McpNoAuth;

  @override
  int get hashCode => jsonKind.hashCode;

  @override
  String toString() => 'McpNoAuth()';
}

/// `Authorization: Bearer <secret>`.
final class McpBearerAuth extends McpAuth {
  /// Creates bearer auth referencing [secretRef].
  const McpBearerAuth(this.secretRef);

  /// JSON discriminator.
  static const jsonKind = 'bearer';

  /// Reference of the token in `McpSecrets`.
  final String secretRef;

  @override
  Set<String> get secretRefs => {secretRef};

  @override
  Map<String, Object?> toJson() => {'kind': jsonKind, 'secretRef': secretRef};

  @override
  bool operator ==(Object other) =>
      other is McpBearerAuth && other.secretRef == secretRef;

  @override
  int get hashCode => Object.hash(jsonKind, secretRef);

  @override
  String toString() => 'McpBearerAuth($secretRef)';
}

/// Own headers whose values are secrets: header name → secret reference.
final class McpHeadersAuth extends McpAuth {
  /// Creates header auth.
  McpHeadersAuth(Map<String, String> secretRefsByHeader)
    : secretRefsByHeader = Map.unmodifiable(secretRefsByHeader);

  /// JSON discriminator.
  static const jsonKind = 'headers';

  /// Header name → secret reference.
  final Map<String, String> secretRefsByHeader;

  @override
  Set<String> get secretRefs => secretRefsByHeader.values.toSet();

  @override
  Map<String, Object?> toJson() => {
    'kind': jsonKind,
    'secretRefs': secretRefsByHeader,
  };

  @override
  bool operator ==(Object other) =>
      other is McpHeadersAuth &&
      const MapEquality<String, String>().equals(
        other.secretRefsByHeader,
        secretRefsByHeader,
      );

  @override
  int get hashCode => Object.hash(
    jsonKind,
    const MapEquality<String, String>().hash(secretRefsByHeader),
  );

  @override
  String toString() => 'McpHeadersAuth(${secretRefsByHeader.keys})';
}

/// OAuth 2.1 as in the MCP authorization spec (discovery, optional dynamic
/// client registration, PKCE). Tokens and the registered client live in
/// `McpSecrets` under [tokenRef] and [clientRef].
final class McpOAuth extends McpAuth {
  /// Creates OAuth auth.
  McpOAuth({
    required this.tokenRef,
    required this.clientRef,
    this.clientId,
    List<String> scopes = const [],
  }) : scopes = List.unmodifiable(scopes);

  /// JSON discriminator.
  static const jsonKind = 'oauth';

  /// Reference of the token set (JSON) in `McpSecrets`.
  final String tokenRef;

  /// Reference of the dynamically registered client (JSON).
  final String clientRef;

  /// Pre-registered public client id; `null` = dynamic registration.
  final String? clientId;

  /// Scopes to request if the server names none.
  final List<String> scopes;

  @override
  Set<String> get secretRefs => {tokenRef, clientRef};

  @override
  Map<String, Object?> toJson() => {
    'kind': jsonKind,
    'tokenRef': tokenRef,
    'clientRef': clientRef,
    if (clientId != null) 'clientId': clientId,
    if (scopes.isNotEmpty) 'scopes': scopes,
  };

  @override
  bool operator ==(Object other) =>
      other is McpOAuth &&
      other.tokenRef == tokenRef &&
      other.clientRef == clientRef &&
      other.clientId == clientId &&
      const ListEquality<String>().equals(other.scopes, scopes);

  @override
  int get hashCode => Object.hash(
    jsonKind,
    tokenRef,
    clientRef,
    clientId,
    const ListEquality<String>().hash(scopes),
  );

  @override
  String toString() => 'McpOAuth(${clientId ?? 'dynamisch'})';
}

/// User setting for one tool of a server (keyed by the MCP tool name).
@immutable
final class McpToolOverride {
  /// Creates an override.
  const McpToolOverride({this.enabled = true, this.risk, this.autoRun = false});

  /// Decodes [toJson].
  factory McpToolOverride.fromJson(Map<String, Object?> json) {
    final risk = _opt<String>(json, 'risk');
    return McpToolOverride(
      enabled: _opt<bool>(json, 'enabled') ?? true,
      autoRun: _opt<bool>(json, 'autoRun') ?? false,
      risk: risk == null
          ? null
          : RiskLevel.values.firstWhere(
              (r) => r.name == risk,
              orElse: () => throw FormatException('Risikostufe "$risk"'),
            ),
    );
  }

  /// Whether the tool is offered at all.
  final bool enabled;

  /// Wished risk level; only applied if stricter than the derived one
  /// (K8 b).
  final RiskLevel? risk;

  /// Whether a tool with base level `write` may run without confirmation
  /// (MCP tools have no undo, so they are confirmed by default). Has no
  /// effect on `read`/`external` tools or under `confirmAll`.
  final bool autoRun;

  /// JSON form.
  Map<String, Object?> toJson() => {
    if (!enabled) 'enabled': false,
    if (risk != null) 'risk': risk!.name,
    if (autoRun) 'autoRun': true,
  };

  @override
  bool operator ==(Object other) =>
      other is McpToolOverride &&
      other.enabled == enabled &&
      other.risk == risk &&
      other.autoRun == autoRun;

  @override
  int get hashCode => Object.hash(enabled, risk, autoRun);

  @override
  String toString() =>
      'McpToolOverride($enabled, ${risk?.name}${autoRun ? ', autoRun' : ''})';
}

/// One configured MCP server. JSON-serializable; contains no secrets, so
/// [toJson] is also the export format.
@immutable
final class McpServerConfig {
  /// Creates a config. [slug] is fixed when the server is added
  /// (`McpNaming.slugFor`) and keeps tool names stable across renames.
  McpServerConfig({
    required this.id,
    required this.name,
    required this.slug,
    required this.url,
    this.transport = McpTransportKind.auto,
    this.auth = const McpNoAuth(),
    this.enabled = true,
    this.sensitive = false,
    this.confirmAll = false,
    this.mayContainUntrustedContent = true,
    Map<String, McpToolOverride> toolOverrides = const {},
  }) : toolOverrides = Map.unmodifiable(toolOverrides);

  /// Decodes [toJson]; throws [FormatException].
  factory McpServerConfig.fromJson(Map<String, Object?> json) {
    final transport = _opt<String>(json, 'transport') ?? 'auto';
    final url = Uri.tryParse(_read<String>(json, 'url'));
    if (url == null) throw const FormatException('McpServerConfig: url');
    return McpServerConfig(
      id: _read(json, 'id'),
      name: _read(json, 'name'),
      slug: _read(json, 'slug'),
      url: url,
      transport: McpTransportKind.values.firstWhere(
        (t) => t.name == transport,
        orElse: () => throw FormatException('Transport "$transport"'),
      ),
      auth: McpAuth.fromJson(_read(json, 'auth')),
      enabled: _opt<bool>(json, 'enabled') ?? true,
      sensitive: _opt<bool>(json, 'sensitive') ?? false,
      confirmAll: _opt<bool>(json, 'confirmAll') ?? false,
      mayContainUntrustedContent:
          _opt<bool>(json, 'mayContainUntrustedContent') ?? true,
      toolOverrides: {
        for (final MapEntry(:key, :value)
            in (_opt<Map<String, Object?>>(json, 'toolOverrides') ?? const {})
                .entries)
          key: value is Map<String, Object?>
              ? McpToolOverride.fromJson(value)
              : throw const FormatException('toolOverrides'),
      },
    );
  }

  /// Stable id chosen by the app (also the cache key).
  final String id;

  /// Display name.
  final String name;

  /// Short name in tool names: `mcp_<slug>__<tool>`.
  final String slug;

  /// Endpoint (Streamable HTTP) or SSE URL (legacy).
  final Uri url;

  /// Transport choice.
  final McpTransportKind transport;

  /// Authentication.
  final McpAuth auth;

  /// Whether the user switched the server on.
  final bool enabled;

  /// Whether tools may only go to providers of the sensitive minimum level.
  final bool sensitive;

  /// Whether every tool of this server needs confirmation (`external`).
  final bool confirmAll;

  /// „Kann unsichere Inhalte enthalten“ (WP157, ADR 0023): the results of
  /// this server may contain text of third parties. Default **on**
  /// (fail-closed). After such a result tools with a network target ask
  /// first.
  final bool mayContainUntrustedContent;

  /// Per-tool settings by MCP tool name.
  final Map<String, McpToolOverride> toolOverrides;

  /// Integration id, `mcp_<slug>`.
  String get integrationId => 'mcp_$slug';

  /// Copy with fields replaced.
  McpServerConfig copyWith({
    String? name,
    Uri? url,
    McpTransportKind? transport,
    McpAuth? auth,
    bool? enabled,
    bool? sensitive,
    bool? confirmAll,
    bool? mayContainUntrustedContent,
    Map<String, McpToolOverride>? toolOverrides,
  }) => McpServerConfig(
    id: id,
    name: name ?? this.name,
    slug: slug,
    url: url ?? this.url,
    transport: transport ?? this.transport,
    auth: auth ?? this.auth,
    enabled: enabled ?? this.enabled,
    sensitive: sensitive ?? this.sensitive,
    confirmAll: confirmAll ?? this.confirmAll,
    mayContainUntrustedContent:
        mayContainUntrustedContent ?? this.mayContainUntrustedContent,
    toolOverrides: toolOverrides ?? this.toolOverrides,
  );

  /// JSON (and export) form without secrets.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'slug': slug,
    'url': url.toString(),
    'transport': transport.name,
    'auth': auth.toJson(),
    'enabled': enabled,
    'sensitive': sensitive,
    'confirmAll': confirmAll,
    if (!mayContainUntrustedContent) 'mayContainUntrustedContent': false,
    if (toolOverrides.isNotEmpty)
      'toolOverrides': {
        for (final MapEntry(:key, :value) in toolOverrides.entries)
          key: value.toJson(),
      },
  };

  @override
  bool operator ==(Object other) =>
      other is McpServerConfig &&
      other.id == id &&
      other.name == name &&
      other.slug == slug &&
      other.url == url &&
      other.transport == transport &&
      other.auth == auth &&
      other.enabled == enabled &&
      other.sensitive == sensitive &&
      other.confirmAll == confirmAll &&
      other.mayContainUntrustedContent == mayContainUntrustedContent &&
      const MapEquality<String, McpToolOverride>().equals(
        other.toolOverrides,
        toolOverrides,
      );

  @override
  int get hashCode => Object.hash(
    id,
    name,
    slug,
    url,
    transport,
    auth,
    enabled,
    sensitive,
    confirmAll,
    mayContainUntrustedContent,
    const MapEquality<String, McpToolOverride>().hash(toolOverrides),
  );

  @override
  String toString() => 'McpServerConfig($id, $name, $url, $auth)';
}

T _read<T>(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is T) return v;
  throw FormatException('MCP-Konfiguration: Feld "$key" fehlt oder ist falsch');
}

T? _opt<T extends Object>(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is T) return v;
  throw FormatException('MCP-Konfiguration: Feld "$key" ist falsch');
}
