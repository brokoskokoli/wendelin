/// Checks tool arguments against the JSON Schema subset tools use.
///
/// Supported keywords: `type` (`object`, `string`, `number`, `integer`,
/// `boolean`, `array`, `null`, or a list of these), `properties`, `required`,
/// `enum`, `items`, `minimum`/`maximum`, `minLength`/`maxLength`,
/// `format: date-time` (ISO 8601 date and time, offset optional) and
/// `additionalProperties` (`false` or a schema). Other keywords
/// (`description`, `default`, …) are ignored.
///
/// Errors are German and name the offending argument, so the model can fix
/// its call.
final class ArgumentValidator {
  /// Creates a validator.
  const ArgumentValidator({this.maxErrors = 5});

  /// At most this many problems are reported (the rest is summarised).
  final int maxErrors;

  /// All problems of [value] against [schema]; empty if valid.
  List<String> errors(Object? value, Map<String, Object?> schema) {
    final out = <String>[];
    _check(value, schema, '', out);
    return out;
  }

  /// A readable message for the model, or `null` if [value] is valid.
  String? validate(Object? value, Map<String, Object?> schema) {
    final all = errors(value, schema);
    if (all.isEmpty) return null;
    final shown = all.take(maxErrors).join('; ');
    final rest = all.length - maxErrors;
    return rest > 0 ? '$shown; und $rest weitere Probleme' : shown;
  }

  /// [args] with integral numbers of `integer` fields as `int` (JSON may
  /// deliver `3.0`), so tools can rely on the declared type. Strictly
  /// decimal strings (`"100"`, `" 21.5 "`) become numbers where the schema
  /// wants `integer`/`number` and not `string` (models often quote numbers);
  /// `"1e3"`, `"100%"` or `"1.5"` for an integer stay unchanged and fail
  /// [validate]. Call before [validate]; other values are returned unchanged.
  Map<String, Object?> normalize(
    Map<String, Object?> args,
    Map<String, Object?> schema,
  ) => _normalize(args, schema)! as Map<String, Object?>;

  Object? _normalize(Object? value, Map<String, Object?> schema) {
    switch (value) {
      case final String s when _numberFromString(s, schema) != null:
        return _numberFromString(s, schema);
      case final double d when _types(schema).contains('integer'):
        return d == d.roundToDouble() ? d.toInt() : d;
      case final List<Object?> list:
        final items = schema['items'];
        return items is Map<String, Object?>
            ? [for (final v in list) _normalize(v, items)]
            : list;
      case final Map<String, Object?> map:
        final props = schema['properties'];
        final additional = schema['additionalProperties'];
        return {
          for (final MapEntry(:key, value: v) in map.entries)
            key: switch (props is Map<String, Object?> ? props[key] : null) {
              final Map<String, Object?> sub => _normalize(v, sub),
              _ when additional is Map<String, Object?> => _normalize(
                v,
                additional,
              ),
              _ => v,
            },
        };
      default:
        return value;
    }
  }

  static final _decimal = RegExp(r'^-?\d+(\.\d+)?$');

  static num? _numberFromString(String s, Map<String, Object?> schema) {
    final types = _types(schema);
    final integer = types.contains('integer');
    if (types.contains('string') || !(integer || types.contains('number'))) {
      return null;
    }
    final t = s.trim();
    if (!_decimal.hasMatch(t)) return null;
    final n = t.contains('.') ? double.parse(t) : int.parse(t);
    if (types.contains('number') || n is int) return n;
    // integer only: "70.0" is fine, "1.5" is not.
    return n == n.roundToDouble() ? n.toInt() : null;
  }

  static List<Object?> _types(Map<String, Object?> schema) {
    final type = schema['type'];
    return type is List ? type : [type];
  }

  void _check(
    Object? value,
    Map<String, Object?> schema,
    String path,
    List<String> out,
  ) {
    final where = path.isEmpty ? 'Argumente' : 'Argument „$path“';

    final type = schema['type'];
    if (type != null) {
      final types = type is List ? type.whereType<String>().toList() : [type];
      if (!types.any((t) => _hasType(value, t))) {
        out.add(
          '$where: erwartet ${types.join(' oder ')}, '
          'erhalten ${_typeName(value)}',
        );
        return;
      }
    }

    final allowed = schema['enum'];
    if (allowed is List && !allowed.any((a) => _jsonEquals(a, value))) {
      out.add(
        '$where: erlaubt sind nur ${allowed.map(_show).join(', ')}, '
        'erhalten ${_show(value)}',
      );
    }

    switch (value) {
      case final String s:
        _checkString(s, schema, where, out);
      case final num n:
        _checkNumber(n, schema, where, out);
      case final List<Object?> list:
        final items = schema['items'];
        if (items is Map<String, Object?>) {
          for (final (i, item) in list.indexed) {
            _check(item, items, '$path[$i]', out);
          }
        }
      case final Map<String, Object?> map:
        _checkObject(map, schema, path, where, out);
      default:
    }
  }

  void _checkString(
    String s,
    Map<String, Object?> schema,
    String where,
    List<String> out,
  ) {
    final length = s.runes.length;
    final min = schema['minLength'];
    if (min is int && length < min) {
      out.add('$where: mindestens $min Zeichen, erhalten $length');
    }
    final max = schema['maxLength'];
    if (max is int && length > max) {
      out.add('$where: höchstens $max Zeichen, erhalten $length');
    }
    if (schema['format'] == 'date-time' && !isIsoDateTime(s)) {
      out.add(
        '$where: erwartet Datum mit Uhrzeit nach ISO 8601 '
        '(z. B. 2026-10-14T10:00:00+02:00), erhalten ${_show(s)}',
      );
    }
  }

  void _checkNumber(
    num n,
    Map<String, Object?> schema,
    String where,
    List<String> out,
  ) {
    final min = schema['minimum'];
    if (min is num && n < min) {
      out.add('$where: muss mindestens $min sein, erhalten $n');
    }
    final max = schema['maximum'];
    if (max is num && n > max) {
      out.add('$where: darf höchstens $max sein, erhalten $n');
    }
  }

  void _checkObject(
    Map<String, Object?> map,
    Map<String, Object?> schema,
    String path,
    String where,
    List<String> out,
  ) {
    String child(String key) => path.isEmpty ? key : '$path.$key';

    final required = schema['required'];
    if (required is List) {
      for (final key in required.whereType<String>()) {
        if (!map.containsKey(key)) {
          out.add('$where: Pflichtfeld „${child(key)}“ fehlt');
        }
      }
    }
    final props = schema['properties'];
    final properties = props is Map<String, Object?>
        ? props
        : const <String, Object?>{};
    final additional = schema['additionalProperties'];
    for (final MapEntry(:key, value: v) in map.entries) {
      final sub = properties[key];
      if (sub is Map<String, Object?>) {
        _check(v, sub, child(key), out);
      } else if (additional == false) {
        final known = properties.keys.join(', ');
        out.add(
          '$where: unbekanntes Feld „${child(key)}“'
          '${known.isEmpty ? '' : ' (erlaubt: $known)'}',
        );
      } else if (additional is Map<String, Object?>) {
        _check(v, additional, child(key), out);
      }
    }
  }

  static bool _hasType(Object? value, Object? type) => switch (type) {
    'object' => value is Map<String, Object?>,
    'array' => value is List,
    'string' => value is String,
    'boolean' => value is bool,
    'number' => value is num,
    'integer' => value is int || (value is double && value == value.round()),
    'null' => value == null,
    _ => true, // unknown type keywords are not enforced
  };

  static String _typeName(Object? value) => switch (value) {
    null => 'null',
    Map() => 'object',
    List() => 'array',
    String() => 'string',
    bool() => 'boolean',
    int() => 'integer',
    num() => 'number',
    _ => value.runtimeType.toString(),
  };

  static String _show(Object? value) {
    final text = value is String ? '"$value"' : '$value';
    return text.length > 60 ? '${text.substring(0, 57)}…' : text;
  }

  static bool _jsonEquals(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_jsonEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      return a.keys.every((k) => b.containsKey(k) && _jsonEquals(a[k], b[k]));
    }
    return a == b;
  }
}

final _isoDateTime = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?'
  r'(?:[Zz]|[+-](\d{2}):?(\d{2}))?$',
);

/// Whether [s] is an ISO 8601 date with time, e.g. `2026-10-14T10:00`,
/// `2026-10-14T10:00:00Z` or `2026-10-14T10:00:00.5+02:00`. Without offset
/// the time is local to the device time zone. Field ranges are checked
/// (no 31 February, no 25:00).
bool isIsoDateTime(String s) {
  final m = _isoDateTime.firstMatch(s);
  if (m == null) return false;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final (year, month, day) = (g(1), g(2), g(3));
  if (month < 1 || month > 12 || day < 1) return false;
  final daysInMonth = DateTime.utc(year, month + 1, 0).day;
  return day <= daysInMonth &&
      g(4) <= 23 &&
      g(5) <= 59 &&
      g(6) <= 59 &&
      g(7) <= 23 &&
      g(8) <= 59;
}
