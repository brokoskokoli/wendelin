import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import 'http_secret_refs.dart';
import 'http_tool_definition.dart';

/// Types offered for an argument in the simple list.
const httpArgTypes = ['string', 'integer', 'number', 'boolean'];

/// One argument of the simple list (becomes a schema property).
final class HttpArgDraft {
  /// Creates an argument.
  HttpArgDraft({
    this.name = '',
    this.type = 'string',
    this.required = false,
    this.description = '',
  });

  /// Property name (also the placeholder `{name}`).
  String name;

  /// JSON-Schema type, one of [httpArgTypes].
  String type;

  /// Whether the argument is required.
  bool required;

  /// Description for the model.
  String description;
}

/// A plain (non-secret) header; the value may contain placeholders.
final class HttpHeaderDraft {
  /// Creates a header.
  HttpHeaderDraft({this.name = '', this.value = ''});

  /// Header name.
  String name;

  /// Value template.
  String value;
}

/// A secret header: the value lives in the `SecretStore` and is only ever
/// replaced, never shown.
final class HttpSecretHeaderDraft {
  /// Creates a secret header.
  HttpSecretHeaderDraft({this.name = '', this.stored = false, this.newValue});

  /// Header name.
  String name;

  /// Whether a value is stored already.
  bool stored;

  /// Replacement typed by the user (`null` = keep the stored one).
  String? newValue;
}

/// How the tool authenticates.
enum HttpAuthKind {
  /// No secret.
  none('Keine'),

  /// `Authorization: Bearer <Token>`.
  bearer('Bearer-Token'),

  /// One or more secret headers (API keys).
  headers('Geheime Header');

  const HttpAuthKind(this.label);

  /// German label.
  final String label;
}

/// Editable state of the HTTP-tool editor. Builds the
/// [HttpToolDefinition] ([toDefinition]) and the secret changes
/// ([secretChanges]); the secrets themselves are never part of the
/// definition.
final class HttpToolDraft {
  /// An empty draft for a new tool with [id].
  HttpToolDraft.empty(this.id) : isNew = true;

  /// The draft of the stored [d]; [storedRefs] are the secret references
  /// that have a value in the store.
  HttpToolDraft.of(HttpToolDefinition d, {Set<String> storedRefs = const {}})
    : id = d.id,
      isNew = false,
      name = d.name,
      description = d.description,
      method = d.method,
      url = d.urlTemplate,
      bodyFormat = d.bodyFormat,
      risk = d.risk,
      autoRun = d.autoRun,
      mayContainUntrustedContent = d.mayContainUntrustedContent,
      sensitive = d.sensitive,
      homeNetwork = d.homeNetwork,
      enabled = d.enabled,
      timeoutSeconds = '${d.timeout.inSeconds}',
      responsePath = d.responsePath {
    headers = [
      for (final e in d.headers.entries)
        HttpHeaderDraft(name: e.key, value: e.value),
    ];
    switch (d.auth) {
      case ApiKeyAuth(:final secretRef, headerName: null):
        auth = HttpAuthKind.bearer;
        bearerStored = storedRefs.contains(secretRef);
      case ApiKeyAuth(:final secretRef, :final headerName?):
        auth = HttpAuthKind.headers;
        secretHeaders = [
          HttpSecretHeaderDraft(
            name: headerName,
            stored: storedRefs.contains(secretRef),
          ),
        ];
      case CustomHeadersAuth(:final secretRefsByHeader):
        auth = HttpAuthKind.headers;
        secretHeaders = [
          for (final e in secretRefsByHeader.entries)
            HttpSecretHeaderDraft(
              name: e.key,
              stored: storedRefs.contains(e.value),
            ),
        ];
      case NoAuth() || OAuthPkceAuth():
        auth = HttpAuthKind.none;
    }
    final template = d.bodyTemplate;
    body = template == null
        ? ''
        : const JsonEncoder.withIndent('  ').convert(template);
    final args = _argsOf(d.inputSchema);
    if (args == null) {
      rawSchema = true;
      schemaText = const JsonEncoder.withIndent('  ').convert(d.inputSchema);
    } else {
      this.args = args;
    }
  }

  /// Stable id of the definition.
  final String id;

  /// Whether the tool is not stored yet.
  final bool isNew;

  /// Tool name without `http__`.
  String name = '';

  /// Description for the model.
  String description = '';

  /// HTTP method.
  HttpMethod method = HttpMethod.get;

  /// URL template.
  String url = 'https://';

  /// Plain headers.
  List<HttpHeaderDraft> headers = [];

  /// Authentication.
  HttpAuthKind auth = HttpAuthKind.none;

  /// Whether a bearer token is stored.
  bool bearerStored = false;

  /// New bearer token (`null` = keep).
  String? bearerNew;

  /// Secret headers.
  List<HttpSecretHeaderDraft> secretHeaders = [];

  /// Body template as JSON text (empty = no body).
  String body = '';

  /// Encoding of the body.
  HttpBodyFormat bodyFormat = HttpBodyFormat.json;

  /// Arguments of the simple list.
  List<HttpArgDraft> args = [];

  /// Whether [schemaText] is used instead of [args].
  bool rawSchema = false;

  /// Own JSON schema (raw mode).
  String schemaText = '{\n  "type": "object",\n  "properties": {}\n}';

  /// Risk level chosen by the user (never below the method's suggestion).
  RiskLevel risk = RiskLevel.read;

  /// „Ohne Nachfrage ausführen (kein Rückgängig)“.
  bool autoRun = false;

  /// „Kann unsichere Inhalte enthalten“ (default on, WP157).
  bool mayContainUntrustedContent = true;

  /// Only to providers above the sensitive minimum.
  bool sensitive = false;

  /// Target in the home network.
  bool homeNetwork = false;

  /// Whether the tool is offered.
  bool enabled = true;

  /// Time limit in seconds (text field).
  String timeoutSeconds = '${httpToolDefaultTimeout.inSeconds}';

  /// Kept from imports (not editable).
  String? responsePath;

  /// Changes the method and moves the risk to the method's suggestion
  /// (the user may raise it again).
  void setMethod(HttpMethod m) {
    method = m;
    risk = m.suggestedRisk;
    if (body.trim().isNotEmpty && !m.allowsBody) body = '';
  }

  /// Risk levels the user may choose: the method's suggestion and above.
  List<RiskLevel> get riskChoices => [
    for (final r in RiskLevel.values)
      if (r.index >= method.suggestedRisk.index) r,
  ];

  /// Whether „Ohne Nachfrage ausführen“ can apply (method and choice
  /// `write`).
  bool get autoRunAvailable =>
      method.suggestedRisk == RiskLevel.write && risk == RiskLevel.write;

  /// The JSON schema of the arguments; throws [FormatException].
  Map<String, Object?> schema() {
    if (rawSchema) {
      final Object? json;
      try {
        json = jsonDecode(schemaText);
      } on FormatException {
        throw const FormatException('Schema ist kein gültiges JSON');
      }
      if (json is! Map<String, Object?>) {
        throw const FormatException('Schema muss ein JSON-Objekt sein');
      }
      return json;
    }
    final names = <String>{};
    for (final a in args) {
      final n = a.name.trim();
      if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(n)) {
        throw FormatException('Argument „$n“: nur Buchstaben, Ziffern und „_“');
      }
      if (!names.add(n)) throw FormatException('Argument „$n“ doppelt');
    }
    return {
      'type': 'object',
      'properties': {
        for (final a in args)
          a.name.trim(): {
            'type': a.type,
            if (a.description.trim().isNotEmpty)
              'description': a.description.trim(),
          },
      },
      if (args.any((a) => a.required))
        'required': [
          for (final a in args)
            if (a.required) a.name.trim(),
        ],
    };
  }

  /// Names of the arguments (from the list or the raw schema); empty if
  /// the raw schema is invalid.
  Set<String> argNames() {
    try {
      final props = schema()['properties'];
      return props is Map<String, Object?> ? props.keys.toSet() : const {};
    } on FormatException {
      return const {};
    }
  }

  /// Types of the arguments by name (for the test inputs).
  Map<String, String> argTypes() {
    try {
      final props = schema()['properties'];
      if (props is! Map<String, Object?>) return const {};
      return {
        for (final e in props.entries)
          e.key: switch (e.value) {
            {'type': final String t} => t,
            _ => 'string',
          },
      };
    } on FormatException {
      return const {};
    }
  }

  /// Problem with the name, or `null`: the tool-name rule (letters,
  /// digits, `_`, `-`, up to 58 characters) and uniqueness against
  /// [taken] (case-insensitive).
  String? nameError(Iterable<String> taken) {
    final n = name.trim();
    if (n.isEmpty) return 'Name fehlt';
    if (n.length > httpToolMaxNameLength) {
      return 'Höchstens $httpToolMaxNameLength Zeichen';
    }
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(n)) {
      return 'Nur Buchstaben, Ziffern, „_“ und „-“ (wird zu http__$n)';
    }
    if (taken.any((t) => t.toLowerCase() == n.toLowerCase())) {
      return 'Name ist schon vergeben';
    }
    return null;
  }

  /// The definition; throws [FormatException] with a readable German
  /// message (without the „HTTP-Tool …:“ prefix).
  HttpToolDefinition toDefinition() {
    final timeout = int.tryParse(timeoutSeconds.trim());
    if (timeout == null) {
      throw const FormatException('Zeitlimit in Sekunden angeben');
    }
    Object? bodyTemplate;
    if (body.trim().isNotEmpty) {
      try {
        bodyTemplate = jsonDecode(body);
      } on FormatException {
        throw const FormatException('Body ist kein gültiges JSON');
      }
    }
    final names = <String>{};
    for (final h in secretHeaders) {
      final n = h.name.trim();
      if (n.isEmpty) throw const FormatException('Name eines geheimen Headers');
      if (!names.add(n.toLowerCase())) {
        throw FormatException('Geheimer Header „$n“ doppelt');
      }
    }
    final AuthMethod authMethod = switch (auth) {
      HttpAuthKind.none => const NoAuth(),
      HttpAuthKind.bearer => ApiKeyAuth(httpBearerRef(id)),
      HttpAuthKind.headers when secretHeaders.isEmpty => const NoAuth(),
      HttpAuthKind.headers => CustomHeadersAuth({
        for (final h in secretHeaders)
          h.name.trim(): httpHeaderRef(id, h.name.trim()),
      }),
    };
    final plain = <String, String>{};
    for (final h in headers) {
      final n = h.name.trim();
      if (n.isEmpty && h.value.isEmpty) continue;
      if (plain.keys.any((k) => k.toLowerCase() == n.toLowerCase())) {
        throw FormatException('Header „$n“ doppelt');
      }
      plain[n] = h.value;
    }
    final d = HttpToolDefinition(
      id: id,
      name: name.trim(),
      description: description.trim(),
      method: method,
      urlTemplate: url.trim(),
      inputSchema: schema(),
      headers: plain,
      bodyTemplate: bodyTemplate,
      bodyFormat: bodyFormat,
      auth: authMethod,
      risk: risk.index < method.suggestedRisk.index
          ? method.suggestedRisk
          : risk,
      autoRun: autoRun && autoRunAvailable,
      mayContainUntrustedContent: mayContainUntrustedContent,
      sensitive: sensitive,
      homeNetwork: homeNetwork,
      enabled: enabled,
      timeout: Duration(seconds: timeout),
      responsePath: responsePath,
    );
    try {
      d.validate();
    } on FormatException catch (e) {
      throw FormatException(stripHttpToolPrefix(e.message));
    }
    return d;
  }

  /// First problem of the draft (name, then the definition), or `null`.
  String? problem(Iterable<String> taken) {
    final n = nameError(taken);
    if (n != null) return n;
    try {
      toDefinition();
      final missing = missingSecrets();
      if (missing != null) return missing;
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  /// A hint if a secret has no value yet, else `null`.
  String? missingSecrets() {
    if (auth == HttpAuthKind.bearer &&
        !bearerStored &&
        (bearerNew ?? '').isEmpty) {
      return 'Bearer-Token fehlt';
    }
    if (auth == HttpAuthKind.headers) {
      for (final h in secretHeaders) {
        if (!h.stored && (h.newValue ?? '').isEmpty) {
          return 'Wert für „${h.name.trim()}“ fehlt';
        }
      }
    }
    return null;
  }

  /// Secret references with a new value to store.
  Map<String, String?> secretChanges() => {
    if (auth == HttpAuthKind.bearer && (bearerNew ?? '').isNotEmpty)
      httpBearerRef(id): bearerNew,
    if (auth == HttpAuthKind.headers)
      for (final h in secretHeaders)
        if ((h.newValue ?? '').isNotEmpty)
          httpHeaderRef(id, h.name.trim()): h.newValue,
  };

  /// The arguments of the simple list for [schema], or `null` if it uses
  /// more than the list can show (then the raw mode is used).
  static List<HttpArgDraft>? _argsOf(Map<String, Object?> schema) {
    final props = schema['properties'] ?? const <String, Object?>{};
    final required = schema['required'] ?? const <Object?>[];
    if (schema.keys.any(
          (k) => !const {'type', 'properties', 'required'}.contains(k),
        ) ||
        props is! Map<String, Object?> ||
        required is! List<Object?>) {
      return null;
    }
    final out = <HttpArgDraft>[];
    for (final MapEntry(key: name, value: p) in props.entries) {
      if (p is! Map<String, Object?> ||
          p.keys.any((k) => k != 'type' && k != 'description') ||
          !httpArgTypes.contains(p['type']) ||
          (p['description'] != null && p['description'] is! String)) {
        return null;
      }
      out.add(
        HttpArgDraft(
          name: name,
          type: p['type']! as String,
          required: required.contains(name),
          description: (p['description'] as String?) ?? '',
        ),
      );
    }
    return out;
  }
}

/// [message] without the leading „HTTP-Tool „name“: “.
String stripHttpToolPrefix(String message) =>
    message.replaceFirst(RegExp(r'^HTTP-Tool( „[^“]*“)?: '), '');

/// Parses the test input [text] of an argument of [type]; `null` for
/// empty input. Throws [FormatException].
Object? parseHttpArg(String text, String type) {
  final t = text.trim();
  if (t.isEmpty) return null;
  return switch (type) {
    'integer' =>
      int.tryParse(t) ?? (throw FormatException('„$t“ ist keine ganze Zahl')),
    'number' =>
      num.tryParse(t.replaceAll(',', '.')) ??
          (throw FormatException('„$t“ ist keine Zahl')),
    'boolean' => switch (t.toLowerCase()) {
      'true' || 'ja' || '1' => true,
      'false' || 'nein' || '0' => false,
      _ => throw FormatException('„$t“: ja oder nein'),
    },
    _ => t,
  };
}
