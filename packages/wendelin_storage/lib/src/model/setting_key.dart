import 'package:meta/meta.dart';

/// A typed settings key: [name] plus conversion to and from a JSON value.
///
/// ```dart
/// const wakeWord = SettingKey.boolean('voice.wakeWord', defaultValue: true);
/// await settings.set(wakeWord, false);
/// final on = await settings.get(wakeWord); // false
/// ```
@immutable
final class SettingKey<T extends Object> {
  /// Creates a key with custom conversion. [decode] receives the decoded
  /// JSON value and throws [FormatException] if it does not fit.
  const SettingKey(
    this.name, {
    required this.encode,
    required this.decode,
    this.defaultValue,
  });

  /// A string setting.
  static SettingKey<String> string(String name, {String? defaultValue}) =>
      SettingKey(
        name,
        encode: _identity,
        decode: _cast<String>,
        defaultValue: defaultValue,
      );

  /// A boolean setting.
  static SettingKey<bool> boolean(String name, {bool? defaultValue}) =>
      SettingKey(
        name,
        encode: _identity,
        decode: _cast<bool>,
        defaultValue: defaultValue,
      );

  /// An integer setting.
  static SettingKey<int> integer(String name, {int? defaultValue}) =>
      SettingKey(
        name,
        encode: _identity,
        decode: _cast<int>,
        defaultValue: defaultValue,
      );

  /// A floating-point setting (integers in JSON are accepted).
  static SettingKey<double> decimal(String name, {double? defaultValue}) =>
      SettingKey(
        name,
        encode: _identity,
        decode: (v) => _cast<num>(v).toDouble(),
        defaultValue: defaultValue,
      );

  /// A JSON object setting.
  static SettingKey<Map<String, Object?>> json(
    String name, {
    Map<String, Object?>? defaultValue,
  }) => SettingKey(
    name,
    encode: _identity,
    decode: (v) {
      if (v is Map<String, Object?>) return v;
      throw FormatException('Einstellung $name ist kein Objekt');
    },
    defaultValue: defaultValue,
  );

  /// Storage key.
  final String name;

  /// Converts a value into something `jsonEncode` accepts.
  final Object? Function(T value) encode;

  /// Converts the decoded JSON value back.
  final T Function(Object? json) decode;

  /// Returned by `SettingsRepository.get` when nothing is stored.
  final T? defaultValue;

  static Object? _identity(Object value) => value;

  static V _cast<V>(Object? v) {
    if (v is V) return v;
    throw FormatException('Einstellung: erwartet $V, war ${v.runtimeType}');
  }

  @override
  String toString() => 'SettingKey<$T>($name)';
}
