import 'package:test/test.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

typedef _Case = (
  String name,
  Map<String, Object?> schema,
  Object? value,
  String? error,
);

const _object = {'type': 'object'};

const _event = {
  'type': 'object',
  'properties': {
    'title': {'type': 'string', 'minLength': 1, 'maxLength': 10},
    'start': {'type': 'string', 'format': 'date-time'},
    'count': {'type': 'integer', 'minimum': 1, 'maximum': 5},
    'kind': {
      'type': 'string',
      'enum': ['privat', 'arbeit'],
    },
  },
  'required': ['title', 'start'],
  'additionalProperties': false,
};

final _cases = <_Case>[
  // type
  ('object ok', _object, <String, Object?>{}, null),
  (
    'object statt Liste',
    _object,
    <Object?>[],
    'erwartet object, erhalten array',
  ),
  ('string ok', {'type': 'string'}, 'x', null),
  (
    'string statt Zahl',
    {'type': 'string'},
    3,
    'erwartet string, erhalten integer',
  ),
  ('number nimmt int', {'type': 'number'}, 3, null),
  ('number nimmt double', {'type': 'number'}, 3.5, null),
  ('number lehnt string ab', {'type': 'number'}, '3', 'erwartet number'),
  ('integer ok', {'type': 'integer'}, 3, null),
  ('integer nimmt 3.0', {'type': 'integer'}, 3.0, null),
  (
    'integer lehnt 3.5 ab',
    {'type': 'integer'},
    3.5,
    'erwartet integer, erhalten number',
  ),
  ('boolean ok', {'type': 'boolean'}, false, null),
  ('boolean lehnt 0 ab', {'type': 'boolean'}, 0, 'erwartet boolean'),
  ('array ok', {'type': 'array'}, [1], null),
  (
    'array lehnt Map ab',
    {'type': 'array'},
    <String, Object?>{},
    'erwartet array, erhalten object',
  ),
  ('null ok', {'type': 'null'}, null, null),
  (
    'Typliste',
    {
      'type': ['string', 'null'],
    },
    null,
    null,
  ),
  (
    'Typliste verletzt',
    {
      'type': ['string', 'null'],
    },
    1,
    'erwartet string oder null',
  ),
  ('kein Typ: alles ok', <String, Object?>{}, 42, null),
  // properties / required / additionalProperties
  (
    'Termin gültig',
    _event,
    {'title': 'Tauchen', 'start': '2026-10-14T10:00:00+02:00'},
    null,
  ),
  (
    'Pflichtfeld fehlt',
    _event,
    {'title': 'Tauchen'},
    'Pflichtfeld „start“ fehlt',
  ),
  (
    'unbekanntes Feld',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'x': 1},
    'unbekanntes Feld „x“ (erlaubt: title, start, count, kind)',
  ),
  (
    'Feld falscher Typ',
    _event,
    {'title': 5, 'start': '2026-10-14T10:00'},
    'Argument „title“: erwartet string, erhalten integer',
  ),
  (
    'additionalProperties erlaubt',
    {
      'type': 'object',
      'properties': {
        'a': {'type': 'string'},
      },
    },
    {'b': 1},
    null,
  ),
  (
    'additionalProperties als Schema',
    {
      'type': 'object',
      'additionalProperties': {'type': 'string'},
    },
    {'b': 1},
    'Argument „b“: erwartet string',
  ),
  (
    'additionalProperties false ohne properties',
    {'type': 'object', 'additionalProperties': false},
    {'b': 1},
    'unbekanntes Feld „b“',
  ),
  // enum
  (
    'enum ok',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'kind': 'privat'},
    null,
  ),
  (
    'enum verletzt',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'kind': 'frei'},
    'Argument „kind“: erlaubt sind nur "privat", "arbeit", erhalten "frei"',
  ),
  (
    'enum mit Zahlen 1 == 1.0',
    {
      'enum': [1, 2],
    },
    1.0,
    null,
  ),
  (
    'enum mit Objekt',
    {
      'enum': [
        {
          'a': [1],
        },
      ],
    },
    {
      'a': [1],
    },
    null,
  ),
  (
    'enum mit Objekt verletzt',
    {
      'enum': [
        {
          'a': [1],
        },
      ],
    },
    {
      'a': [2],
    },
    'erlaubt sind nur',
  ),
  (
    'enum Liste ungleich lang',
    {
      'enum': [
        [1],
      ],
    },
    [1, 2],
    'erlaubt sind nur',
  ),
  (
    'enum Objekt anderer Schlüssel',
    {
      'enum': [
        {'a': 1},
      ],
    },
    {'b': 1},
    'erlaubt sind nur',
  ),
  // minimum / maximum
  (
    'minimum Grenze ok',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'count': 1},
    null,
  ),
  (
    'minimum unterschritten',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'count': 0},
    'Argument „count“: muss mindestens 1 sein, erhalten 0',
  ),
  (
    'maximum Grenze ok',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'count': 5},
    null,
  ),
  (
    'maximum überschritten',
    _event,
    {'title': 'a', 'start': '2026-10-14T10:00', 'count': 6},
    'Argument „count“: darf höchstens 5 sein, erhalten 6',
  ),
  // minLength / maxLength
  (
    'minLength verletzt',
    _event,
    {'title': '', 'start': '2026-10-14T10:00'},
    'Argument „title“: mindestens 1 Zeichen, erhalten 0',
  ),
  (
    'maxLength Grenze ok',
    _event,
    {'title': '0123456789', 'start': '2026-10-14T10:00'},
    null,
  ),
  (
    'maxLength verletzt',
    _event,
    {'title': '01234567890', 'start': '2026-10-14T10:00'},
    'Argument „title“: höchstens 10 Zeichen, erhalten 11',
  ),
  (
    'Länge zählt Zeichen, nicht UTF-16',
    {'type': 'string', 'maxLength': 1},
    '😀',
    null,
  ),
  // items
  (
    'items ok',
    {
      'type': 'array',
      'items': {'type': 'string'},
    },
    ['a', 'b'],
    null,
  ),
  (
    'items verletzt mit Pfad',
    {
      'type': 'object',
      'properties': {
        'tags': {
          'type': 'array',
          'items': {'type': 'string'},
        },
      },
    },
    {
      'tags': ['a', 2],
    },
    'Argument „tags[1]“: erwartet string, erhalten integer',
  ),
  (
    'verschachtelter Pfad',
    {
      'type': 'object',
      'properties': {
        'a': {
          'type': 'object',
          'properties': {
            'b': {'type': 'integer'},
          },
        },
      },
    },
    {
      'a': {'b': 'x'},
    },
    'Argument „a.b“',
  ),
  // date-time
  (
    'date-time mit Z',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:00:00Z',
    null,
  ),
  (
    'date-time mit Bruchteil und Offset',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:00:00.250+02:00',
    null,
  ),
  (
    'date-time lokal ohne Sekunden',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:00',
    null,
  ),
  (
    'date-time nur Datum',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14',
    'erwartet Datum mit Uhrzeit nach ISO 8601',
  ),
  (
    'date-time 30. Februar',
    {'type': 'string', 'format': 'date-time'},
    '2026-02-30T10:00:00',
    'ISO 8601',
  ),
  (
    'date-time 29.02. im Schaltjahr',
    {'type': 'string', 'format': 'date-time'},
    '2028-02-29T10:00:00',
    null,
  ),
  (
    'date-time Monat 13',
    {'type': 'string', 'format': 'date-time'},
    '2026-13-01T10:00:00',
    'ISO 8601',
  ),
  (
    'date-time Monat 0',
    {'type': 'string', 'format': 'date-time'},
    '2026-00-01T10:00:00',
    'ISO 8601',
  ),
  (
    'date-time Tag 0',
    {'type': 'string', 'format': 'date-time'},
    '2026-01-00T10:00:00',
    'ISO 8601',
  ),
  (
    'date-time 24 Uhr',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T24:00:00',
    'ISO 8601',
  ),
  (
    'date-time Minute 60',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:60:00',
    'ISO 8601',
  ),
  (
    'date-time Sekunde 60',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:00:60',
    'ISO 8601',
  ),
  (
    'date-time Offset 24 h',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:00:00+24:00',
    'ISO 8601',
  ),
  (
    'date-time Offset Minute 60',
    {'type': 'string', 'format': 'date-time'},
    '2026-10-14T10:00:00+01:60',
    'ISO 8601',
  ),
  (
    'date-time Freitext',
    {'type': 'string', 'format': 'date-time'},
    'morgen 10 Uhr',
    'ISO 8601',
  ),
  (
    'anderes format wird ignoriert',
    {'type': 'string', 'format': 'email'},
    'kein@mail',
    null,
  ),
];

void main() {
  const validator = ArgumentValidator();

  group('ArgumentValidator Tabelle', () {
    for (final (name, schema, value, error) in _cases) {
      test(name, () {
        final message = validator.validate(value, schema);
        if (error == null) {
          expect(message, isNull);
        } else {
          expect(message, contains(error));
        }
      });
    }
  });

  test('mindestens 25 Fälle', () => expect(_cases.length, greaterThan(25)));

  test('Wurzelfehler heißen „Argumente“', () {
    expect(
      validator.validate(<Object?>[], _object),
      'Argumente: erwartet object, erhalten array',
    );
  });

  test('sammelt alle Fehler, zeigt höchstens maxErrors', () {
    const schema = {
      'type': 'object',
      'required': ['a', 'b', 'c'],
    };
    expect(validator.errors(<String, Object?>{}, schema), hasLength(3));
    const short = ArgumentValidator(maxErrors: 2);
    final message = short.validate(<String, Object?>{}, schema)!;
    expect(message, contains('„a“'));
    expect(message, contains('„b“'));
    expect(message, isNot(contains('„c“')));
    expect(message, endsWith('und 1 weitere Probleme'));
    expect(
      const ArgumentValidator(maxErrors: 3)
          .validate(<String, Object?>{}, schema),
      isNot(contains('weitere')),
    );
  });

  test('lange Werte werden in Meldungen gekürzt', () {
    final message = validator.validate('x' * 100, {
      'enum': ['a'],
    })!;
    expect(message, contains('…'));
    expect(message.length, lessThan(120));
  });

  group('normalize', () {
    test('integer: 3.0 → 3, number bleibt double', () {
      final out = validator.normalize(
        {'a': 3.0, 'b': 3.0, 'c': 3.5, 'd': 'x'},
        const {
          'type': 'object',
          'properties': {
            'a': {'type': 'integer'},
            'b': {'type': 'number'},
            'c': {
              'type': ['integer', 'number'],
            },
            'd': {'type': 'string'},
          },
        },
      );
      expect(out['a'], isA<int>());
      expect(out['b'], isA<double>());
      expect(out['c'], 3.5);
      expect(out['d'], 'x');
    });

    test('verschachtelt, items und additionalProperties', () {
      final out = validator.normalize(
        {
          'o': {'n': 1.0},
          'l': [2.0],
          'free': 5.0,
          'raw': [1.0],
        },
        const {
          'type': 'object',
          'properties': {
            'o': {
              'type': 'object',
              'properties': {
                'n': {'type': 'integer'},
              },
            },
            'l': {
              'type': 'array',
              'items': {'type': 'integer'},
            },
            'raw': {'type': 'array'},
          },
          'additionalProperties': {'type': 'integer'},
        },
      );
      expect((out['o']! as Map)['n'], isA<int>());
      expect((out['l']! as List).single, isA<int>());
      expect(out['free'], isA<int>());
      expect((out['raw']! as List).single, isA<double>());
    });

    test('ohne Schema für ein Feld bleibt es unverändert', () {
      expect(
        validator.normalize({'x': 1.0}, const {'type': 'object'})['x'],
        isA<double>(),
      );
    });
  });

  test('isIsoDateTime direkt', () {
    expect(isIsoDateTime('2026-10-14 10:00:00'), isTrue);
    expect(isIsoDateTime('2026-10-14t10:00:00z'), isTrue);
    expect(isIsoDateTime('2026-10-14T10:00:00+0200'), isTrue);
    expect(isIsoDateTime(' 2026-10-14T10:00'), isFalse);
  });
}
