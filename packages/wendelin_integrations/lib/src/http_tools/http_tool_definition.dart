import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'http_target.dart';
import 'http_template.dart';

/// HTTP method of an [HttpToolDefinition].
enum HttpMethod {
  /// `GET` (suggested risk: read).
  get('GET', RiskLevel.read),

  /// `HEAD` (suggested risk: read).
  head('HEAD', RiskLevel.read),

  /// `POST` (suggested risk: write).
  post('POST', RiskLevel.write),

  /// `PUT` (suggested risk: write).
  put('PUT', RiskLevel.write),

  /// `PATCH` (suggested risk: write).
  patch('PATCH', RiskLevel.write),

  /// `DELETE` (suggested risk: external).
  delete('DELETE', RiskLevel.external);

  const HttpMethod(this.verb, this.suggestedRisk);

  /// The verb as sent, e.g. `POST`.
  final String verb;

  /// Risk level proposed for new definitions with this method; also the
  /// lower bound of [HttpToolDefinition.effectiveRisk] (K8 b).
  final RiskLevel suggestedRisk;

  /// Whether requests with this method may carry a body.
  bool get allowsBody => this != get && this != head;

  /// The method for [verb] (case-insensitive); throws [FormatException].
  static HttpMethod parse(String verb) {
    final upper = verb.trim().toUpperCase();
    for (final m in values) {
      if (m.verb == upper) return m;
    }
    throw FormatException('unbekannte HTTP-Methode „$verb“');
  }
}

/// Encoding of the body template.
enum HttpBodyFormat {
  /// JSON (`application/json`); placeholders on value level.
  json,

  /// Form (`application/x-www-form-urlencoded`); flat object of scalars.
  form,
}

/// Current version of the JSON format written by
/// [HttpToolDefinition.toJson] and [exportHttpTools].
const httpToolSchemaVersion = 1;

/// Longest allowed [HttpToolDefinition.name]: `http__` plus the name must
/// fit the 64-character tool-name limit.
const httpToolMaxNameLength = 58;

/// Default [HttpToolDefinition.timeout].
const httpToolDefaultTimeout = Duration(seconds: 15);

/// Longest allowed [HttpToolDefinition.timeout].
const httpToolMaxTimeout = Duration(seconds: 120);

final _namePattern = RegExp(r'^[a-zA-Z0-9_-]+$');
final _headerName = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
final _pathSegment = RegExp(r'^[^.\s]+$');

/// Headers the user may not set in [HttpToolDefinition.headers]: framing
/// and routing headers the client controls.
const _reservedHeaders = {
  'host',
  'content-length',
  'transfer-encoding',
  'connection',
  'upgrade',
  'te',
  'trailer',
  'keep-alive',
  'expect',
};

/// Whether a header called [name] probably carries a secret. Such headers
/// may only be configured through the auth method (secret reference), never
/// as plain template headers – otherwise the value would end up in exports
/// and could be filled from model arguments.
bool isSecretHeaderName(String name) {
  final n = name.toLowerCase();
  if (n == 'authorization' ||
      n == 'proxy-authorization' ||
      n == 'cookie' ||
      n == 'set-cookie') {
    return true;
  }
  return const [
    'token',
    'secret',
    'password',
    'passwd',
    'api-key',
    'apikey',
    'api_key',
    'auth',
    'key',
    'bearer',
    'credential',
    'session',
    'signature',
  ].any(n.contains);
}

/// A user-defined HTTP tool (concept: „Erweiterungswege 1. HTTP-Tool“).
///
/// Holds no secrets: [auth] only references secrets in the `SecretStore`
/// ([ApiKeyAuth] – `Authorization: Bearer …` unless a header name is set –
/// or [CustomHeadersAuth]); they are read just before sending. Construction
/// does not validate (the editor builds partial definitions); [validate]
/// does, and [HttpToolDefinition.fromJson] calls it.
@immutable
final class HttpToolDefinition {
  /// Creates a definition.
  HttpToolDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.method,
    required this.urlTemplate,
    Map<String, Object?> inputSchema = const {
      'type': 'object',
      'properties': <String, Object?>{},
    },
    Map<String, String> headers = const {},
    this.bodyTemplate,
    this.bodyFormat = HttpBodyFormat.json,
    this.auth = const NoAuth(),
    RiskLevel? risk,
    this.sensitive = false,
    this.homeNetwork = false,
    this.enabled = true,
    this.timeout = httpToolDefaultTimeout,
    this.responsePath,
  }) : inputSchema = Map.unmodifiable(inputSchema),
       headers = Map.unmodifiable(headers),
       risk = risk ?? method.suggestedRisk;

  /// Decodes and validates a definition written by [toJson]; throws
  /// [FormatException] with a readable German message.
  factory HttpToolDefinition.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version is! int) {
      throw const FormatException('HTTP-Tool: „schemaVersion“ fehlt');
    }
    if (version < 1 || version > httpToolSchemaVersion) {
      throw FormatException(
        'HTTP-Tool: Version $version wird nicht unterstützt '
        '(diese App kennt bis $httpToolSchemaVersion)',
      );
    }
    final name = json['name'];
    final ctx = 'HTTP-Tool${name is String ? ' „$name“' : ''}';
    T field<T>(String key) {
      final v = json[key];
      if (v is T) return v;
      throw FormatException('$ctx: „$key“ fehlt oder hat den falschen Typ');
    }

    T? optional<T extends Object>(String key) {
      final v = json[key];
      if (v == null || v is T) return v as T?;
      throw FormatException('$ctx: „$key“ hat den falschen Typ');
    }

    E byName<E extends Enum>(List<E> values, String key, E fallback) {
      final v = optional<String>(key);
      if (v == null) return fallback;
      return values.firstWhere(
        (e) => e.name == v,
        orElse: () => throw FormatException('$ctx: „$key“ = „$v“ unbekannt'),
      );
    }

    final AuthMethod auth;
    try {
      final rawAuth = optional<Map<String, Object?>>('auth');
      auth = rawAuth == null ? const NoAuth() : AuthMethod.fromJson(rawAuth);
    } on FormatException catch (e) {
      throw FormatException('$ctx: Anmeldung ungültig (${e.message})');
    }
    final HttpMethod method;
    try {
      method = HttpMethod.parse(field<String>('method'));
    } on FormatException catch (e) {
      throw FormatException('$ctx: ${e.message}');
    }
    final headers = optional<Map<String, Object?>>('headers') ?? const {};
    final timeoutSeconds =
        optional<int>('timeoutSeconds') ?? httpToolDefaultTimeout.inSeconds;
    final definition = HttpToolDefinition(
      id: field<String>('id'),
      name: field<String>('name'),
      description: field<String>('description'),
      method: method,
      urlTemplate: field<String>('url'),
      inputSchema: field<Map<String, Object?>>('inputSchema'),
      headers: {
        for (final e in headers.entries)
          e.key: e.value is String
              ? e.value! as String
              : throw FormatException(
                  '$ctx: Header „${e.key}“ muss ein Text sein',
                ),
      },
      bodyTemplate: json['body'],
      bodyFormat: byName(HttpBodyFormat.values, 'bodyFormat', .json),
      auth: auth,
      risk: byName(RiskLevel.values, 'risk', method.suggestedRisk),
      sensitive: optional<bool>('sensitive') ?? false,
      homeNetwork: optional<bool>('homeNetwork') ?? false,
      enabled: optional<bool>('enabled') ?? true,
      timeout: Duration(seconds: timeoutSeconds),
      responsePath: optional<String>('responsePath'),
    )..validate();
    return definition;
  }

  /// Stable id (survives renames).
  final String id;

  /// Tool name without prefix; the tool is called `http__<name>`.
  final String name;

  /// Description for the model.
  final String description;

  /// JSON Schema (`type: object`) of the arguments; every placeholder must
  /// be one of its properties.
  final Map<String, Object?> inputSchema;

  /// HTTP method.
  final HttpMethod method;

  /// URL template, e.g. `https://ha.example.org/api/states/{entity}`.
  /// Placeholders only in path and query (see `UrlTemplate`).
  final String urlTemplate;

  /// Non-secret headers; values may contain placeholders.
  final Map<String, String> headers;

  /// Body template (JSON value with placeholders on value level), or `null`
  /// for no body.
  final Object? bodyTemplate;

  /// Encoding of [bodyTemplate].
  final HttpBodyFormat bodyFormat;

  /// Authentication (secret references only).
  final AuthMethod auth;

  /// Risk level chosen by the user (see [effectiveRisk]).
  final RiskLevel risk;

  /// Whether the tool may only go to providers above the sensitive minimum
  /// (K10); such tools are offered by the `http_sensitive` integration.
  final bool sensitive;

  /// Whether the user marked the target as home network: the host may then
  /// resolve to private addresses and be reached via plain `http`.
  final bool homeNetwork;

  /// Whether the tool is offered at all.
  final bool enabled;

  /// Time limit for the whole call (connect, redirects, body).
  final Duration timeout;

  /// Optional dot path (`data.items.0.name`) selecting part of a JSON answer.
  final String? responsePath;

  /// Name of the tool in the registry.
  String get toolName => 'http__$name';

  /// The risk the tool runs with: [risk], but never below the method's
  /// [HttpMethod.suggestedRisk] (risk levels can only be raised, K8 b).
  RiskLevel get effectiveRisk =>
      risk.index >= method.suggestedRisk.index ? risk : method.suggestedRisk;

  /// The parsed [urlTemplate]; throws [FormatException].
  UrlTemplate get url => UrlTemplate.parse(urlTemplate);

  /// Checks the definition; throws [FormatException] naming the problem.
  void validate() {
    final ctx = 'HTTP-Tool „$name“';
    if (id.trim().isEmpty) throw FormatException('$ctx: „id“ fehlt');
    if (name.isEmpty ||
        name.length > httpToolMaxNameLength ||
        !_namePattern.hasMatch(name)) {
      throw FormatException(
        '$ctx: Name nur aus Buchstaben, Ziffern, „_“ und „-“, '
        '1–$httpToolMaxNameLength Zeichen',
      );
    }
    if (description.trim().isEmpty) {
      throw FormatException('$ctx: Beschreibung fehlt');
    }
    if (description.length > 2000) {
      throw FormatException('$ctx: Beschreibung zu lang (höchstens 2000)');
    }
    final properties = _schemaProperties(ctx);
    final UrlTemplate parsed;
    try {
      parsed = url;
    } on FormatException catch (e) {
      throw FormatException('$ctx: ${e.message}');
    }
    if (parsed.origin.isScheme('http') &&
        !homeNetwork &&
        !isHomeNetworkHost(parsed.origin.host)) {
      throw FormatException(
        '$ctx: „http“ nur für Heimnetz-Ziele – „https“ verwenden oder das '
        'Ziel als Heimnetz markieren',
      );
    }
    final placeholders = <String>{...parsed.placeholders};
    final secretHeaders = _secretHeaderNames(ctx);
    for (final e in headers.entries) {
      final lower = e.key.toLowerCase();
      if (!_headerName.hasMatch(e.key)) {
        throw FormatException('$ctx: ungültiger Header-Name „${e.key}“');
      }
      if (_reservedHeaders.contains(lower)) {
        throw FormatException('$ctx: Header „${e.key}“ setzt die App selbst');
      }
      if (isSecretHeaderName(e.key) || secretHeaders.contains(lower)) {
        throw FormatException(
          '$ctx: Header „${e.key}“ sieht geheim aus – bitte als Secret in '
          'der Anmeldung hinterlegen',
        );
      }
      if (_hasControlChars(e.value)) {
        throw FormatException(
          '$ctx: Header „${e.key}“ enthält Zeilenumbrüche oder Steuerzeichen',
        );
      }
      if (e.value.codeUnits.any((c) => c > 0x7e)) {
        throw FormatException(
          '$ctx: Header „${e.key}“ darf nur ASCII-Zeichen enthalten',
        );
      }
      try {
        placeholders.addAll(templatePlaceholders(e.value));
      } on FormatException catch (x) {
        throw FormatException('$ctx: Header „${e.key}“: ${x.message}');
      }
    }
    if (bodyTemplate != null) {
      if (!method.allowsBody) {
        throw FormatException('$ctx: ${method.verb} hat keinen Body');
      }
      try {
        placeholders.addAll(bodyPlaceholders(bodyTemplate, bodyFormat));
      } on FormatException catch (x) {
        throw FormatException('$ctx: Body: ${x.message}');
      }
    }
    for (final p in placeholders) {
      if (!properties.contains(p)) {
        throw FormatException(
          '$ctx: Platzhalter „{$p}“ ist kein Argument im Schema',
        );
      }
    }
    if (timeout < const Duration(seconds: 1) || timeout > httpToolMaxTimeout) {
      throw FormatException(
        '$ctx: Zeitlimit 1–${httpToolMaxTimeout.inSeconds} s',
      );
    }
    final path = responsePath;
    if (path != null &&
        (path.isEmpty || !path.split('.').every(_pathSegment.hasMatch))) {
      throw FormatException(
        '$ctx: „responsePath“ als Punkt-Pfad angeben, z. B. „data.0.name“',
      );
    }
  }

  Set<String> _schemaProperties(String ctx) {
    if (inputSchema['type'] != 'object') {
      throw FormatException('$ctx: Schema muss „type: object“ haben');
    }
    final props = inputSchema['properties'] ?? const <String, Object?>{};
    if (props is! Map<Object?, Object?> ||
        props.keys.any((k) => k is! String)) {
      throw FormatException('$ctx: Schema-„properties“ muss ein Objekt sein');
    }
    final required = inputSchema['required'] ?? const <Object?>[];
    if (required is! List<Object?> ||
        required.any((r) => r is! String || !props.containsKey(r))) {
      throw FormatException(
        '$ctx: Schema-„required“ nennt unbekannte Argumente',
      );
    }
    return props.keys.cast<String>().toSet();
  }

  /// Lower-case names of the headers [auth] sends.
  Set<String> _secretHeaderNames(String ctx) => switch (auth) {
    NoAuth() => const {},
    ApiKeyAuth(:final headerName) => {
      if (headerName != null && !_headerName.hasMatch(headerName))
        throw FormatException('$ctx: ungültiger Header-Name „$headerName“'),
      (headerName ?? 'authorization').toLowerCase(),
    },
    CustomHeadersAuth(:final secretRefsByHeader) => {
      for (final h in secretRefsByHeader.keys)
        if (!_headerName.hasMatch(h) ||
            _reservedHeaders.contains(h.toLowerCase()))
          throw FormatException('$ctx: ungültiger Header-Name „$h“')
        else
          h.toLowerCase(),
    },
    OAuthPkceAuth() => throw FormatException(
      '$ctx: OAuth wird für HTTP-Tools nicht unterstützt',
    ),
  };

  /// Encodes the definition (with [httpToolSchemaVersion]); contains no
  /// secrets, only secret references.
  Map<String, Object?> toJson() => {
    'schemaVersion': httpToolSchemaVersion,
    'id': id,
    'name': name,
    'description': description,
    'method': method.verb,
    'url': urlTemplate,
    'inputSchema': inputSchema,
    if (headers.isNotEmpty) 'headers': headers,
    if (bodyTemplate != null) 'body': bodyTemplate,
    if (bodyTemplate != null) 'bodyFormat': bodyFormat.name,
    'auth': auth.toJson(),
    'risk': risk.name,
    'sensitive': sensitive,
    'homeNetwork': homeNetwork,
    'enabled': enabled,
    'timeoutSeconds': timeout.inSeconds,
    if (responsePath != null) 'responsePath': responsePath,
  };

  /// A copy with the given fields replaced.
  HttpToolDefinition copyWith({
    String? name,
    String? description,
    HttpMethod? method,
    String? urlTemplate,
    Map<String, Object?>? inputSchema,
    Map<String, String>? headers,
    AuthMethod? auth,
    RiskLevel? risk,
    bool? sensitive,
    bool? homeNetwork,
    bool? enabled,
    Duration? timeout,
  }) => HttpToolDefinition(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    method: method ?? this.method,
    urlTemplate: urlTemplate ?? this.urlTemplate,
    inputSchema: inputSchema ?? this.inputSchema,
    headers: headers ?? this.headers,
    bodyTemplate: bodyTemplate,
    bodyFormat: bodyFormat,
    auth: auth ?? this.auth,
    risk: risk ?? this.risk,
    sensitive: sensitive ?? this.sensitive,
    homeNetwork: homeNetwork ?? this.homeNetwork,
    enabled: enabled ?? this.enabled,
    timeout: timeout ?? this.timeout,
    responsePath: responsePath,
  );

  @override
  bool operator ==(Object other) =>
      other is HttpToolDefinition &&
      const DeepCollectionEquality().equals(other.toJson(), toJson());

  @override
  int get hashCode => const DeepCollectionEquality().hash(toJson());

  @override
  String toString() => 'HttpToolDefinition($toolName, ${method.verb})';
}

bool _hasControlChars(String s) =>
    s.codeUnits.any((c) => (c < 0x20 && c != 0x09) || c == 0x7f);

/// Whether [s] contains CR, LF or other control characters (TAB allowed).
bool hasHeaderControlChars(String s) => _hasControlChars(s);

/// Checks that [definitions] can live side by side: each valid, unique
/// ids and tool names (case-insensitive). Throws [FormatException].
void validateHttpToolSet(Iterable<HttpToolDefinition> definitions) {
  final ids = <String>{};
  final names = <String>{};
  for (final d in definitions) {
    d.validate();
    if (!ids.add(d.id)) {
      throw FormatException('HTTP-Tool „${d.name}“: Id „${d.id}“ doppelt');
    }
    if (!names.add(d.name.toLowerCase())) {
      throw FormatException('HTTP-Tool „${d.name}“: Name doppelt vergeben');
    }
  }
}

/// Export document of [definitions] (no secrets, with schema version).
Map<String, Object?> exportHttpTools(Iterable<HttpToolDefinition> definitions) {
  final list = definitions.toList();
  validateHttpToolSet(list);
  return {
    'schemaVersion': httpToolSchemaVersion,
    'httpTools': [for (final d in list) d.toJson()],
  };
}

/// Reads an export written by [exportHttpTools]; throws [FormatException]
/// with a readable message for the first invalid definition.
List<HttpToolDefinition> importHttpTools(Map<String, Object?> json) {
  final version = json['schemaVersion'];
  if (version is! int || version < 1 || version > httpToolSchemaVersion) {
    throw FormatException(
      'HTTP-Tools: Version ${version ?? 'fehlt'} wird nicht unterstützt',
    );
  }
  final raw = json['httpTools'];
  if (raw is! List<Object?>) {
    throw const FormatException('HTTP-Tools: Liste „httpTools“ fehlt');
  }
  final list = [
    for (final (i, e) in raw.indexed)
      e is Map<String, Object?>
          ? HttpToolDefinition.fromJson(e)
          : throw FormatException(
              'HTTP-Tools: Eintrag ${i + 1} ist kein Objekt',
            ),
  ];
  validateHttpToolSet(list);
  return list;
}
