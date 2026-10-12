import 'dart:math';

/// Injectable source of unique ids.
abstract interface class IdGenerator {
  /// Returns a new id, distinct from all previous ones of this generator.
  String next();
}

/// Random RFC 4122 version-4 UUIDs (lowercase, with dashes).
final class UuidV4Generator implements IdGenerator {
  /// Creates a generator; [random] defaults to [Random.secure].
  UuidV4Generator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String next() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

/// Predictable ids for tests: `<prefix>1`, `<prefix>2`, …
final class SequentialIdGenerator implements IdGenerator {
  /// Creates a generator starting at [start].
  SequentialIdGenerator({this.prefix = 'id-', int start = 1}) : _next = start;

  /// Prefix of every id.
  final String prefix;

  int _next;

  @override
  String next() => '$prefix${_next++}';
}
