import 'dart:convert';
import 'dart:typed_data';

/// Hex and canonical-JSON helpers of the attestation (RFC 8785 subset: the
/// ACI documents contain only ASCII keys and whole numbers).
abstract final class AttestCodec {
  /// Lower-case hex of [bytes].
  static String hex(List<int> bytes) {
    final b = StringBuffer();
    for (final v in bytes) {
      b.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return b.toString();
  }

  /// Decodes [hex]; throws [FormatException] for odd length or non-hex.
  static Uint8List unhex(String hex) {
    if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
      throw const FormatException('Hex erwartet');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// `sha256:<hex>` as used by the gateway for digests.
  static String prefixed(Uint8List digest) => 'sha256:${hex(digest)}';

  /// Canonical JSON (compact, keys sorted by code unit) of [value].
  /// Throws [FormatException] for non-integer numbers.
  static String jcs(Object? value) {
    final b = StringBuffer();
    _write(b, value);
    return b.toString();
  }

  /// UTF-8 bytes of [jcs].
  static Uint8List jcsBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(jcs(value)));

  static void _write(StringBuffer b, Object? v) {
    switch (v) {
      case null:
        b.write('null');
      case bool():
        b.write(v);
      case int():
        b.write(v);
      case double() when v == v.truncateToDouble() && v.abs() < 1e15:
        b.write(v.toInt());
      case double():
        throw const FormatException('JCS: nur ganze Zahlen unterstützt');
      case String():
        b.write(jsonEncode(v));
      case List<Object?>():
        b.write('[');
        for (var i = 0; i < v.length; i++) {
          if (i > 0) b.write(',');
          _write(b, v[i]);
        }
        b.write(']');
      case Map<Object?, Object?>():
        final keys = v.keys.cast<String>().toList()..sort();
        b.write('{');
        for (var i = 0; i < keys.length; i++) {
          if (i > 0) b.write(',');
          b.write(jsonEncode(keys[i]));
          b.write(':');
          _write(b, v[keys[i]]);
        }
        b.write('}');
      default:
        throw FormatException('JCS: Typ ${v.runtimeType} nicht unterstützt');
    }
  }
}
