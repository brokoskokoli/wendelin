import 'dart:math';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('Clock', () {
    test('SystemClock returns the current time', () {
      final before = DateTime.now();
      final now = const SystemClock().now();
      final after = DateTime.now();
      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
    });

    test('FixedClock stays fixed until set or advanced', () {
      final start = DateTime.utc(2026, 10, 12, 9);
      final c = FixedClock(start);
      expect(c.now(), start);
      expect(c.now(), start);
      c.advance(const Duration(minutes: 5));
      expect(c.now(), DateTime.utc(2026, 10, 12, 9, 5));
      c.advance(const Duration(minutes: -10));
      expect(c.now(), DateTime.utc(2026, 10, 12, 8, 55));
      c.set(DateTime.utc(2030));
      expect(c.now(), DateTime.utc(2030));
    });
  });

  group('UuidV4Generator', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    test('produces RFC 4122 v4 format with secure default', () {
      final g = UuidV4Generator();
      for (var i = 0; i < 200; i++) {
        expect(g.next(), matches(pattern));
      }
    });

    test('ids are unique', () {
      final g = UuidV4Generator();
      final ids = {for (var i = 0; i < 1000; i++) g.next()};
      expect(ids, hasLength(1000));
    });

    test('version and variant bits are forced even for extreme bytes', () {
      expect(
        UuidV4Generator(random: _ConstRandom(255)).next(),
        'ffffffff-ffff-4fff-bfff-ffffffffffff',
      );
      expect(
        UuidV4Generator(random: _ConstRandom(0)).next(),
        '00000000-0000-4000-8000-000000000000',
      );
    });

    test('injected random makes ids reproducible', () {
      expect(
        UuidV4Generator(random: Random(42)).next(),
        UuidV4Generator(random: Random(42)).next(),
      );
    });
  });

  group('SequentialIdGenerator', () {
    test('counts up with prefix', () {
      final g = SequentialIdGenerator();
      expect([g.next(), g.next(), g.next()], ['id-1', 'id-2', 'id-3']);
    });

    test('custom prefix and start', () {
      final g = SequentialIdGenerator(prefix: 'call_', start: 0);
      expect([g.next(), g.next()], ['call_0', 'call_1']);
      expect(g.prefix, 'call_');
    });
  });
}

class _ConstRandom implements Random {
  _ConstRandom(this.value);

  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
