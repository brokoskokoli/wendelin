import 'dart:convert';

/// Largest accepted input schema (encoded JSON, bytes): a bigger schema
/// would eat the model's context on every request.
const maxSchemaBytes = 8 * 1024;

/// Keywords the argument validator of `wendelin_tools` enforces.
const supportedSchemaKeywords = {
  'type',
  'properties',
  'required',
  'enum',
  'items',
  'minimum',
  'maximum',
  'minLength',
  'maxLength',
  'format',
  'additionalProperties',
};

/// Keywords that only describe and need no enforcement.
const _annotationKeywords = {
  r'$schema',
  r'$id',
  r'$comment',
  'title',
  'description',
  'default',
  'examples',
  'deprecated',
  'readOnly',
  'writeOnly',
};

/// Formats the validator checks; other `format` values are not enforced.
const _supportedFormats = {'date-time'};

/// The input schema of an MCP tool, prepared for the tool system.
///
/// The schema is passed on to the model unchanged (only `type: object` is
/// added if missing). The argument validator of the tool runtime enforces
/// the subset in [supportedSchemaKeywords]; everything else is listed in
/// [unsupported] (path and keyword, e.g. `properties.when: anyOf`), so it
/// is documented instead of silently dropped. The server validates such
/// parts itself and answers with an error the model can read.
final class McpSchema {
  McpSchema._(this.schema, this.unsupported, this.encodedBytes);

  /// Prepares [raw] (`inputSchema` from `tools/list`).
  factory McpSchema.from(Map<String, Object?> raw) {
    final schema = Map<String, Object?>.of(raw);
    schema.putIfAbsent('type', () => 'object');
    final unsupported = <String>[];
    _walk(schema, '', unsupported);
    return McpSchema._(
      Map.unmodifiable(schema),
      List.unmodifiable(unsupported),
      utf8.encode(jsonEncode(schema)).length,
    );
  }

  /// Schema for the tool spec.
  final Map<String, Object?> schema;

  /// Schema parts the runtime does not enforce (`path: keyword`).
  final List<String> unsupported;

  /// Size of the encoded schema in bytes (see [maxSchemaBytes]).
  final int encodedBytes;

  /// Whether the schema fits the context budget.
  bool get withinBudget => encodedBytes <= maxSchemaBytes;

  static void _walk(Map<String, Object?> node, String path, List<String> out) {
    String at(String key) => path.isEmpty ? key : '$path.$key';
    for (final MapEntry(:key, :value) in node.entries) {
      if (_annotationKeywords.contains(key)) continue;
      if (!supportedSchemaKeywords.contains(key)) {
        out.add('${path.isEmpty ? '(Wurzel)' : path}: $key');
        continue;
      }
      switch (key) {
        case 'format' when !_supportedFormats.contains(value):
          out.add('${path.isEmpty ? '(Wurzel)' : path}: format $value');
        case 'properties' when value is Map<String, Object?>:
          for (final MapEntry(key: name, value: sub) in value.entries) {
            if (sub is Map<String, Object?>) _walk(sub, at(name), out);
          }
        case 'items' when value is Map<String, Object?>:
          _walk(value, at('items'), out);
        case 'items' when value is List<Object?>:
          out.add('${at('items')}: Tupel');
        case 'additionalProperties' when value is Map<String, Object?>:
          _walk(value, at('additionalProperties'), out);
        default:
      }
    }
  }
}
