// WP201: the origin lattice (none / server / unknown) and its fail-closed
// defaults.
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  const none = ContentOrigin.none;
  const unknown = ContentOrigin.unknown;
  const x = ContentOrigin.server('X');
  const y = ContentOrigin.server('Y');

  group('merge', () {
    final cases = <(String, ContentOrigin, ContentOrigin, ContentOrigin)>[
      ('none + none', none, none, none),
      ('none + X', none, x, x),
      ('X + none', x, none, x),
      ('X + X', x, x, x),
      ('X + Y', x, y, unknown),
      ('Y + X', y, x, unknown),
      ('none + unknown', none, unknown, unknown),
      ('unknown + none', unknown, none, unknown),
      ('X + unknown', x, unknown, unknown),
      ('unknown + X', unknown, x, unknown),
      ('unknown + unknown', unknown, unknown, unknown),
    ];
    for (final (name, a, b, expected) in cases) {
      test(name, () => expect(a.merge(b), expected));
    }
    test('unknown ist absorbierend über eine Folge', () {
      final all = [x, unknown, x, x].fold(none, (a, b) => a.merge(b));
      expect(all, unknown);
    });
  });

  group('encode/decode', () {
    for (final o in [none, unknown, x, const ContentOrigin.server('a:b')]) {
      test('Rundlauf $o', () => expect(ContentOrigin.decode(o.encode()), o));
    }
    test('null und leer = none', () {
      expect(ContentOrigin.decode(null), none);
      expect(ContentOrigin.decode(''), none);
    });
    test('Unlesbares = unknown (fail-closed)', () {
      for (final bad in ['s:', 'x', 's', '??', 'S:X']) {
        expect(ContentOrigin.decode(bad), unknown, reason: bad);
      }
    });
  });

  test('Gleichheit nach Server-ID, nicht nach Typ allein', () {
    expect(x, const ContentOrigin.server('X'));
    expect(x, isNot(y));
    expect(none, isNot(unknown));
  });

  test('Tool ohne ContentOriginAware = unknown (fail-closed)', () {
    expect(contentOriginOf(Object()), unknown);
    expect(contentOriginOf(_Srv()), x);
  });
}

final class _Srv implements ContentOriginAware {
  @override
  ContentOrigin get contentOrigin => const ContentOrigin.server('X');
}
