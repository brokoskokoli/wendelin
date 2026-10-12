import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

/// Decodes [data] as a JSON object or throws [MalformedResponseException].
Map<String, Object?> decodeObject(String data, String label) {
  Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    throw MalformedResponseException('$label: ungültiges JSON im Stream');
  }
  if (decoded is Map<String, Object?>) return decoded;
  throw MalformedResponseException('$label: JSON-Objekt erwartet');
}

/// [value] as a JSON object, or `null`.
Map<String, Object?>? asMap(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// [value] as a JSON array, or an empty list.
List<Object?> asList(Object? value) =>
    value is List<Object?> ? value : const [];

/// [value] as a string, or `null`.
String? asString(Object? value) => value is String ? value : null;

/// [value] as an int, or `null`.
int? asInt(Object? value) => value is int ? value : null;

/// Tries to decode [body] as an error object and returns a readable detail
/// (`error.message`, `message` or a shortened raw body).
String errorDetail(String body) {
  try {
    final decoded = jsonDecode(body);
    final map = asMap(decoded);
    final error = map?['error'];
    final message =
        asString(asMap(error)?['message']) ??
        asString(error) ??
        asString(map?['message']) ??
        asString(map?['detail']);
    if (message != null) return message;
  } on FormatException {
    // fall through to raw body
  }
  final trimmed = body.trim();
  return trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
}
