/// Raised by [ToolArgs] when an argument is missing or malformed; tools
/// report it as an error outcome.
final class InvalidArgumentsException implements Exception {
  /// Creates the exception with a German [message] for the model.
  const InvalidArgumentsException(this.message);

  /// What is wrong, e.g. „„start“ fehlt“.
  final String message;

  @override
  String toString() => 'InvalidArgumentsException: $message';
}

/// Typed, defensive access to tool arguments.
///
/// The tool runtime validates against the schema first; this is the second
/// line of defence, so every reader throws [InvalidArgumentsException]
/// instead of a cast error.
extension type const ToolArgs(Map<String, Object?> raw) {
  /// Whether [key] is present and not `null`.
  bool has(String key) => raw[key] != null;

  /// A required, non-blank string (trimmed).
  String requireString(String key) {
    final v = optString(key);
    if (v == null || v.isEmpty) {
      throw InvalidArgumentsException('„$key“ fehlt');
    }
    return v;
  }

  /// An optional string (trimmed); `null` if absent.
  String? optString(String key) {
    final v = raw[key];
    if (v == null) return null;
    if (v is! String) {
      throw InvalidArgumentsException('„$key“ muss ein Text sein');
    }
    return v.trim();
  }

  /// An optional integer within [min]..[max]; integral doubles (`30.0`) are
  /// accepted because some models send them.
  int? optInt(String key, {int? min, int? max}) {
    final v = raw[key];
    if (v == null) return null;
    final int i;
    if (v is int) {
      i = v;
    } else if (v is double && v == v.roundToDouble() && v.isFinite) {
      i = v.toInt();
    } else {
      throw InvalidArgumentsException('„$key“ muss eine ganze Zahl sein');
    }
    if ((min != null && i < min) || (max != null && i > max)) {
      throw InvalidArgumentsException(
        '„$key“ muss zwischen ${min ?? '-∞'} und ${max ?? '∞'} liegen',
      );
    }
    return i;
  }

  /// A required integer within [min]..[max].
  int requireInt(String key, {int? min, int? max}) {
    final i = optInt(key, min: min, max: max);
    if (i == null) throw InvalidArgumentsException('„$key“ fehlt');
    return i;
  }

  /// An optional boolean; `null` if absent.
  bool? optBool(String key) {
    final v = raw[key];
    if (v == null) return null;
    if (v is! bool) {
      throw InvalidArgumentsException('„$key“ muss true oder false sein');
    }
    return v;
  }

  /// An optional list of strings; `null` if absent.
  List<String>? optStringList(String key) {
    final v = raw[key];
    if (v == null) return null;
    if (v is! List<Object?> || v.any((e) => e is! String)) {
      throw InvalidArgumentsException('„$key“ muss eine Liste von Texten sein');
    }
    return [for (final e in v) (e! as String).trim()];
  }

  /// An optional list of integers within [min]..[max]; `null` if absent.
  List<int>? optIntList(String key, {int? min, int? max}) {
    final v = raw[key];
    if (v == null) return null;
    if (v is! List<Object?>) {
      throw InvalidArgumentsException('„$key“ muss eine Liste sein');
    }
    return [
      for (var i = 0; i < v.length; i++)
        ToolArgs({'$key[$i]': v[i]}).requireInt('$key[$i]', min: min, max: max),
    ];
  }
}
