import 'dart:convert';

import 'package:meta/meta.dart';

import 'errors.dart';

/// Protocol versions the client speaks, newest first; the first is
/// requested in `initialize`.
const mcpProtocolVersions = [
  '2025-11-25',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// JSON-RPC error code for unknown methods (server requests the client
/// does not support).
const rpcMethodNotFound = -32601;

/// A JSON-RPC 2.0 message.
@immutable
sealed class JsonRpcMessage {
  const JsonRpcMessage();

  /// Decodes one message or a batch (array); throws [McpException]
  /// ([McpErrorKind.protocol]) for anything that is not JSON-RPC 2.0.
  static List<JsonRpcMessage> decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw const McpException(McpErrorKind.protocol, 'Antwort ist kein JSON');
    }
    if (json is List<Object?>) return [for (final m in json) _one(m)];
    return [_one(json)];
  }

  static JsonRpcMessage _one(Object? json) {
    if (json is! Map<String, Object?> || json['jsonrpc'] != '2.0') {
      throw const McpException(
        McpErrorKind.protocol,
        'Keine JSON-RPC-2.0-Nachricht',
      );
    }
    final id = json['id'];
    final method = json['method'];
    final params = json['params'];
    final paramMap = params is Map<String, Object?> ? params : null;
    if (method is String) {
      return id == null
          ? JsonRpcNotification(method, paramMap)
          : JsonRpcRequest(id, method, paramMap);
    }
    if (id == null && json['error'] == null) {
      throw const McpException(McpErrorKind.protocol, 'Antwort ohne id');
    }
    final error = json['error'];
    if (error is Map<String, Object?>) {
      final code = error['code'];
      final message = error['message'];
      return JsonRpcError(
        id,
        code is int ? code : 0,
        message is String ? message : 'Fehler',
      );
    }
    if (!json.containsKey('result')) {
      throw const McpException(
        McpErrorKind.protocol,
        'Antwort ohne result und error',
      );
    }
    return JsonRpcResponse(id!, json['result']);
  }

  /// The wire form.
  Map<String, Object?> toJson();

  /// [toJson] encoded.
  String encode() => jsonEncode(toJson());
}

/// A request (expects an answer with the same [id]).
final class JsonRpcRequest extends JsonRpcMessage {
  /// Creates a request.
  const JsonRpcRequest(this.id, this.method, [this.params]);

  /// Request id (int or string).
  final Object id;

  /// Method name, e.g. `tools/call`.
  final String method;

  /// Parameters.
  final Map<String, Object?>? params;

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  };
}

/// A notification (no answer).
final class JsonRpcNotification extends JsonRpcMessage {
  /// Creates a notification.
  const JsonRpcNotification(this.method, [this.params]);

  /// Method name, e.g. `notifications/tools/list_changed`.
  final String method;

  /// Parameters.
  final Map<String, Object?>? params;

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'method': method,
    if (params != null) 'params': params,
  };
}

/// A successful answer.
final class JsonRpcResponse extends JsonRpcMessage {
  /// Creates a response.
  const JsonRpcResponse(this.id, this.result);

  /// Id of the request.
  final Object id;

  /// Result value.
  final Object? result;

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };
}

/// An error answer.
final class JsonRpcError extends JsonRpcMessage {
  /// Creates an error.
  const JsonRpcError(this.id, this.code, this.message);

  /// Id of the request (may be `null` for parse errors).
  final Object? id;

  /// Error code.
  final int code;

  /// Error text from the server.
  final String message;

  @override
  Map<String, Object?> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

/// What the server reported in `initialize`.
@immutable
final class McpServerInfo {
  /// Creates server info.
  const McpServerInfo({
    required this.protocolVersion,
    required this.name,
    this.version,
    this.instructions,
    this.toolsListChanged = false,
  });

  /// Parses an `initialize` result; throws [McpException] (protocol).
  factory McpServerInfo.fromResult(Object? result) {
    if (result is! Map<String, Object?>) {
      throw const McpException(
        McpErrorKind.protocol,
        'initialize: kein Objekt',
      );
    }
    final version = result['protocolVersion'];
    if (version is! String) {
      throw const McpException(
        McpErrorKind.protocol,
        'initialize: protocolVersion fehlt',
      );
    }
    if (!mcpProtocolVersions.contains(version)) {
      throw McpException(
        McpErrorKind.protocol,
        'Protokollversion $version wird nicht unterstützt',
      );
    }
    final info = result['serverInfo'];
    final caps = result['capabilities'];
    final tools = caps is Map<String, Object?> ? caps['tools'] : null;
    final instructions = result['instructions'];
    return McpServerInfo(
      protocolVersion: version,
      name: info is Map<String, Object?> && info['name'] is String
          ? info['name']! as String
          : '?',
      version: info is Map<String, Object?> && info['version'] is String
          ? info['version']! as String
          : null,
      instructions: instructions is String ? instructions : null,
      toolsListChanged:
          tools is Map<String, Object?> && tools['listChanged'] == true,
    );
  }

  /// Negotiated protocol version.
  final String protocolVersion;

  /// `serverInfo.name`.
  final String name;

  /// `serverInfo.version`.
  final String? version;

  /// Optional usage hints of the server (not passed to the model).
  final String? instructions;

  /// Whether the server announces `notifications/tools/list_changed`.
  final bool toolsListChanged;

  @override
  String toString() => 'McpServerInfo($name $version, $protocolVersion)';
}

/// Behaviour hints of a tool. They come from the server and are **not
/// trustworthy**; they only select the default risk level.
@immutable
final class McpToolAnnotations {
  /// Creates annotations.
  const McpToolAnnotations({
    this.title,
    this.readOnlyHint,
    this.destructiveHint,
    this.idempotentHint,
    this.openWorldHint,
  });

  /// Parses the `annotations` object (unknown or mistyped fields ignored).
  factory McpToolAnnotations.fromJson(Map<String, Object?> json) {
    bool? b(String k) => json[k] is bool ? json[k]! as bool : null;
    return McpToolAnnotations(
      title: json['title'] is String ? json['title']! as String : null,
      readOnlyHint: b('readOnlyHint'),
      destructiveHint: b('destructiveHint'),
      idempotentHint: b('idempotentHint'),
      openWorldHint: b('openWorldHint'),
    );
  }

  /// Display title.
  final String? title;

  /// Tool claims not to change anything.
  final bool? readOnlyHint;

  /// Tool claims to delete or overwrite.
  final bool? destructiveHint;

  /// Repeating has no further effect.
  final bool? idempotentHint;

  /// Interacts with the outside world.
  final bool? openWorldHint;

  /// JSON form.
  Map<String, Object?> toJson() => {
    if (title != null) 'title': title,
    if (readOnlyHint != null) 'readOnlyHint': readOnlyHint,
    if (destructiveHint != null) 'destructiveHint': destructiveHint,
    if (idempotentHint != null) 'idempotentHint': idempotentHint,
    if (openWorldHint != null) 'openWorldHint': openWorldHint,
  };

  @override
  bool operator ==(Object other) =>
      other is McpToolAnnotations &&
      other.title == title &&
      other.readOnlyHint == readOnlyHint &&
      other.destructiveHint == destructiveHint &&
      other.idempotentHint == idempotentHint &&
      other.openWorldHint == openWorldHint;

  @override
  int get hashCode => Object.hash(
    title,
    readOnlyHint,
    destructiveHint,
    idempotentHint,
    openWorldHint,
  );
}

/// A tool as listed by `tools/list`.
@immutable
final class McpToolInfo {
  /// Creates tool info.
  const McpToolInfo({
    required this.name,
    this.title,
    this.description = '',
    this.inputSchema = const {'type': 'object'},
    this.annotations = const McpToolAnnotations(),
  });

  /// Parses one entry of `tools/list`; throws [McpException] (protocol).
  factory McpToolInfo.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw const McpException(McpErrorKind.protocol, 'Tool ohne Namen');
    }
    final schema = json['inputSchema'];
    final annotations = json['annotations'];
    return McpToolInfo(
      name: name,
      title: json['title'] is String ? json['title']! as String : null,
      description: json['description'] is String
          ? json['description']! as String
          : '',
      inputSchema: schema is Map<String, Object?>
          ? schema
          : const {'type': 'object'},
      annotations: annotations is Map<String, Object?>
          ? McpToolAnnotations.fromJson(annotations)
          : const McpToolAnnotations(),
    );
  }

  /// MCP tool name (as the server knows it).
  final String name;

  /// Display title.
  final String? title;

  /// Description for the model.
  final String description;

  /// JSON Schema of the arguments.
  final Map<String, Object?> inputSchema;

  /// Behaviour hints.
  final McpToolAnnotations annotations;

  /// JSON form (cache).
  Map<String, Object?> toJson() => {
    'name': name,
    if (title != null) 'title': title,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': annotations.toJson(),
  };

  @override
  String toString() => 'McpToolInfo($name)';
}

/// The result of `tools/call` as sent by the server.
@immutable
final class McpCallResult {
  /// Creates a result.
  McpCallResult({
    List<Map<String, Object?>> content = const [],
    this.structuredContent,
    this.isError = false,
  }) : content = List.unmodifiable(content);

  /// Parses a `tools/call` result; throws [McpException] (protocol).
  factory McpCallResult.fromResult(Object? result) {
    if (result is! Map<String, Object?>) {
      throw const McpException(
        McpErrorKind.protocol,
        'tools/call: kein Objekt',
      );
    }
    final content = result['content'];
    return McpCallResult(
      content: [
        if (content is List<Object?>)
          for (final c in content)
            if (c is Map<String, Object?>) c,
      ],
      structuredContent: result['structuredContent'],
      isError: result['isError'] == true,
    );
  }

  /// Content blocks (`text`, `image`, `audio`, `resource_link`,
  /// `resource`).
  final List<Map<String, Object?>> content;

  /// Structured result, if any.
  final Object? structuredContent;

  /// Whether the tool reports a failure.
  final bool isError;
}
