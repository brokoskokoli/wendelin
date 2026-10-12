// Interne Helfer zum typsicheren Lesen von JSON-Maps (nicht exportiert).

/// Reads a required field of type [T] from [json] or throws a
/// [FormatException] naming [context] and [key].
T readField<T>(Map<String, Object?> json, String key, String context) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    '$context: Feld "$key" fehlt oder hat falschen Typ '
    '(erwartet $T, war ${value.runtimeType})',
  );
}

/// Reads an optional field of type [T]; `null` or missing yields `null`.
T? readOptional<T extends Object>(
  Map<String, Object?> json,
  String key,
  String context,
) {
  final value = json[key];
  if (value == null) return null;
  if (value is T) return value;
  throw FormatException(
    '$context: Feld "$key" hat falschen Typ '
    '(erwartet $T, war ${value.runtimeType})',
  );
}

/// Reads a JSON object field (a `Map<String, Object?>`).
Map<String, Object?> readMap(
  Map<String, Object?> json,
  String key,
  String context,
) => _asMap(readField<Map<Object?, Object?>>(json, key, context), context);

/// Reads a JSON array field whose elements are JSON objects.
List<Map<String, Object?>> readMapList(
  Map<String, Object?> json,
  String key,
  String context,
) => [
  for (final e in readField<List<Object?>>(json, key, context))
    if (e is Map<Object?, Object?>)
      _asMap(e, context)
    else
      throw FormatException('$context: "$key" enthält kein Objekt'),
];

/// Reads an enum value by its [Enum.name].
T readEnum<T extends Enum>(
  Map<String, Object?> json,
  String key,
  List<T> values,
  String context,
) {
  final name = readField<String>(json, key, context);
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('$context: unbekannter Wert "$name" für "$key"');
}

Map<String, Object?> _asMap(Map<Object?, Object?> m, String context) {
  final result = <String, Object?>{};
  m.forEach((k, v) {
    if (k is! String) {
      throw FormatException('$context: Schlüssel ist kein String');
    }
    result[k] = v;
  });
  return result;
}

/// Reads a JSON array field whose elements are strings.
List<String> readStringList(
  Map<String, Object?> json,
  String key,
  String context,
) => [
  for (final e in readField<List<Object?>>(json, key, context))
    if (e is String)
      e
    else
      throw FormatException('$context: "$key" enthält keinen String'),
];

/// Reads a JSON object field whose values are strings.
Map<String, String> readStringMap(
  Map<String, Object?> json,
  String key,
  String context,
) {
  final result = <String, String>{};
  readMap(json, key, context).forEach((k, v) {
    if (v is! String) {
      throw FormatException('$context: "$key.$k" ist kein String');
    }
    result[k] = v;
  });
  return result;
}
