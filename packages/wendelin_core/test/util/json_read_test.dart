import 'package:test/test.dart';
import 'package:wendelin_core/src/util/json_read.dart';

enum _Color { red, green }

Matcher _formatError(List<String> parts) => isA<FormatException>().having(
  (e) => e.message,
  'message',
  allOf([for (final p in parts) contains(p)]),
);

void main() {
  group('readField', () {
    test('returns the value when the type matches', () {
      expect(readField<String>({'a': 'x'}, 'a', 'Ctx'), 'x');
      expect(readField<int>({'n': 3}, 'n', 'Ctx'), 3);
    });

    test('missing key throws FormatException naming context and key', () {
      expect(
        () => readField<String>({}, 'name', 'Nachricht'),
        throwsA(_formatError(['Nachricht', '"name"'])),
      );
    });

    test('wrong type throws FormatException naming context and key', () {
      expect(
        () => readField<String>({'name': 42}, 'name', 'Nachricht'),
        throwsA(_formatError(['Nachricht', '"name"', 'String', 'int'])),
      );
    });
  });

  group('readOptional', () {
    test('returns the value when the type matches', () {
      expect(readOptional<String>({'a': 'x'}, 'a', 'Ctx'), 'x');
    });

    test('missing key yields null', () {
      expect(readOptional<String>({}, 'a', 'Ctx'), isNull);
    });

    test('explicit null yields null', () {
      expect(readOptional<String>({'a': null}, 'a', 'Ctx'), isNull);
    });

    test('wrong type throws FormatException', () {
      expect(
        () => readOptional<String>({'a': true}, 'a', 'Ctx'),
        throwsA(_formatError(['Ctx', '"a"'])),
      );
    });
  });

  group('readMap', () {
    test('reads a valid object', () {
      final result = readMap(
        {
          'o': <Object?, Object?>{'k': 1, 'l': 'v'},
        },
        'o',
        'Ctx',
      );
      expect(result, {'k': 1, 'l': 'v'});
      expect(result, isA<Map<String, Object?>>());
    });

    test('non-string key throws FormatException', () {
      expect(
        () => readMap(
          {
            'o': <Object?, Object?>{1: 'v'},
          },
          'o',
          'Ctx',
        ),
        throwsA(_formatError(['Ctx', 'Schlüssel'])),
      );
    });

    test('missing field throws FormatException', () {
      expect(
        () => readMap({}, 'o', 'Ctx'),
        throwsA(_formatError(['Ctx', '"o"'])),
      );
    });
  });

  group('readMapList', () {
    test('reads a list of valid objects', () {
      final result = readMapList(
        {
          'l': <Object?>[
            <Object?, Object?>{'a': 1},
            <String, Object?>{'b': 'x'},
          ],
        },
        'l',
        'Ctx',
      );
      expect(result, [
        {'a': 1},
        {'b': 'x'},
      ]);
    });

    test('element that is not an object throws FormatException', () {
      expect(
        () => readMapList(
          {
            'l': <Object?>[
              <String, Object?>{'a': 1},
              'kein Objekt',
            ],
          },
          'l',
          'Ctx',
        ),
        throwsA(_formatError(['Ctx', '"l"'])),
      );
    });

    test('element with non-string key throws FormatException', () {
      expect(
        () => readMapList(
          {
            'l': <Object?>[
              <Object?, Object?>{1: 'v'},
            ],
          },
          'l',
          'Ctx',
        ),
        throwsA(_formatError(['Ctx', 'Schlüssel'])),
      );
    });
  });

  group('readEnum', () {
    test('known name yields the value', () {
      expect(readEnum({'c': 'green'}, 'c', _Color.values, 'Ctx'), _Color.green);
    });

    test('unknown name throws FormatException naming the value', () {
      expect(
        () => readEnum({'c': 'blue'}, 'c', _Color.values, 'Ctx'),
        throwsA(_formatError(['Ctx', '"blue"', '"c"'])),
      );
    });
  });

  group('readStringList', () {
    test('reads a list of strings', () {
      expect(
        readStringList(
          {
            'l': <Object?>['a', 'b'],
          },
          'l',
          'Ctx',
        ),
        ['a', 'b'],
      );
    });

    test('non-string element throws FormatException', () {
      expect(
        () => readStringList(
          {
            'l': <Object?>['a', 2],
          },
          'l',
          'Ctx',
        ),
        throwsA(_formatError(['Ctx', '"l"'])),
      );
    });
  });

  group('readStringMap', () {
    test('reads a map of strings', () {
      expect(
        readStringMap(
          {
            'm': <Object?, Object?>{'a': 'x', 'b': 'y'},
          },
          'm',
          'Ctx',
        ),
        {'a': 'x', 'b': 'y'},
      );
    });

    test('non-string value throws FormatException', () {
      expect(
        () => readStringMap(
          {
            'm': <String, Object?>{'a': 'x', 'b': 1},
          },
          'm',
          'Ctx',
        ),
        throwsA(_formatError(['Ctx', '"m.b"'])),
      );
    });
  });

  group('deepUnmodifiable', () {
    Map<String, Object?> original() => {
      'n': 1,
      'inner': <String, Object?>{
        'list': <Object?>[
          1,
          <String, Object?>{'x': 'y'},
        ],
      },
    };

    test('nested maps and lists are unmodifiable', () {
      final copy = deepUnmodifiable(original())! as Map<String, Object?>;
      final inner = copy['inner']! as Map<String, Object?>;
      final list = inner['list']! as List<Object?>;
      final innerMost = list[1]! as Map<String, Object?>;

      expect(() => copy['z'] = 1, throwsUnsupportedError);
      expect(() => inner['z'] = 1, throwsUnsupportedError);
      expect(() => list.add(2), throwsUnsupportedError);
      expect(() => list[0] = 2, throwsUnsupportedError);
      expect(() => innerMost['x'] = 'z', throwsUnsupportedError);
      expect(copy, original());
    });

    test('scalars are returned unchanged', () {
      expect(deepUnmodifiable(null), isNull);
      expect(deepUnmodifiable(42), 42);
      expect(deepUnmodifiable(1.5), 1.5);
      expect(deepUnmodifiable('s'), 's');
      expect(deepUnmodifiable(true), isTrue);
    });

    test('non-string key throws ArgumentError', () {
      expect(
        () => deepUnmodifiable(<Object?, Object?>{1: 'v'}),
        throwsArgumentError,
      );
      expect(
        () => deepUnmodifiable(<Object?>[
          <Object?, Object?>{1: 'v'},
        ]),
        throwsArgumentError,
      );
    });

    test('the original stays modifiable', () {
      final source = original();
      deepUnmodifiable(source);
      source['z'] = 2;
      final inner = source['inner']! as Map<String, Object?>;
      inner['w'] = 3;
      final list = inner['list']! as List<Object?>;
      list.add(4);
      (list[1]! as Map<String, Object?>)['x'] = 'changed';
      expect(source['z'], 2);
      expect(inner['w'], 3);
      expect(list, hasLength(3));
    });
  });
}
