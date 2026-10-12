import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  const l = PrivacyLevel.local;
  const t = PrivacyLevel.tee;
  const e = PrivacyLevel.eu;
  const s = PrivacyLevel.standard;

  // (level, other, level.isAtLeast(other)) – all 16 combinations.
  const table = <(PrivacyLevel, PrivacyLevel, bool)>[
    (l, l, true),
    (l, t, true),
    (l, e, true),
    (l, s, true),
    (t, l, false),
    (t, t, true),
    (t, e, true),
    (t, s, true),
    (e, l, false),
    (e, t, false),
    (e, e, true),
    (e, s, true),
    (s, l, false),
    (s, t, false),
    (s, e, false),
    (s, s, true),
  ];

  test('table covers all 16 combinations', () {
    expect(table.map((r) => (r.$1, r.$2)).toSet(), hasLength(16));
  });

  for (final (level, other, expected) in table) {
    test('${level.name}.isAtLeast(${other.name}) == $expected', () {
      expect(level.isAtLeast(other), expected);
    });
  }
}
