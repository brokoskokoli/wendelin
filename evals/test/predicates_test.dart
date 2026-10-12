import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  final time = EvalTime.parse('2026-10-14T09:00', 'Europe/Berlin');

  /// (spec, value, passes)
  final table = <(Object?, Object?, bool)>[
    // Gleichheit
    ('Tauchen', 'tauchen ', true),
    ('Tauchen', 'Tauchen gehen', false),
    (600, 600, true),
    (600, 600.0, true),
    (600, '600', true),
    (600, 60, false),
    (true, true, true),
    (true, 'true', false),
    ([1, 2, 3], [3, 2, 1], true),
    ([1, 2, 3], [1, 2], false),
    ([1, 2, 2], [1, 2, 3], false),
    (
      {
        'eq': {'a': 1},
      },
      {'a': 1},
      true,
    ),
    (
      {
        'eq': {'a': 1},
      },
      {'a': 2},
      false,
    ),
    (
      {
        'eq': {'a': 1},
      },
      {'b': 1},
      false,
    ),
    (
      {
        'eq': {'a': 1},
      },
      {'a': 1, 'b': 2},
      false,
    ),
    ({'eq': null}, null, true),
    ({'eq': 'x'}, null, false),
    // contains
    ({'contains': 'Tauchen'}, 'Tauchen mit Jonas', true),
    ({'contains': 'tauchen'}, 'TAUCHEN', true),
    ({'contains': 'Tauchen'}, 'Schwimmen', false),
    (
      {
        'contains': ['Milch', 'Eier'],
      },
      ['2 Liter Milch', 'Eier'],
      true,
    ),
    (
      {
        'contains': ['Milch', 'Eier'],
      },
      ['Milch'],
      false,
    ),
    ({'contains': 'x'}, null, false),
    ({'contains': 391}, 'Das sind 391.', true),
    (
      {
        'contains_any': ['Vollmond', 'Mond'],
      },
      'nächster Mond',
      true,
    ),
    (
      {
        'contains_any': ['a', 'b'],
      },
      'c',
      false,
    ),
    // matches
    ({'matches': r'^evt-\w+$'}, 'EVT-zahnarzt', true),
    ({'matches': r'^\d+$'}, 'abc', false),
    ({'matches': r'^\d+$'}, 42, true),
    // at
    ({'at': '+1d 10:00'}, '2026-10-15T10:00', true),
    ({'at': '+1d 10:00'}, '2026-10-15T10:00:00+02:00', true),
    ({'at': '+1d 10:00'}, '2026-10-15T08:00:00Z', true),
    ({'at': '+1d 10:00'}, '2026-10-15T10:15', false),
    ({'at': '+1d 10:00', 'tol_min': 15}, '2026-10-15T10:15', true),
    ({'at': '+1d 10:00', 'tol_min': 15}, '2026-10-15T09:44', false),
    ({'at': '+1d 10:00'}, '2026-10-15', false),
    ({'at': '+1d'}, '2026-10-15T23:00', true),
    ({'at': '+1d'}, '2026-10-16', false),
    ({'at': '+1d 10:00'}, 'morgen', false),
    ({'at': '+1d 10:00'}, 5, false),
    // date
    ({'date': 'sat'}, '2026-10-17', true),
    ({'date': 'sat'}, '2026-10-17T00:00', true),
    ({'date': 'sat'}, '2026-10-18', false),
    ({'date': 'sat'}, 'Samstag', false),
    ({'date': 'sat'}, null, false),
    // clock
    ({'clock': '06:30'}, '6:30', true),
    ({'clock': '06:30'}, '06:30:00', true),
    ({'clock': '06:30'}, '18:30', false),
    ({'clock': '06:30'}, 'halb sieben', false),
    ({'clock': '06:30'}, 630, false),
    // range
    ({'min': 1, 'max': 5}, 3, true),
    ({'min': 1, 'max': 5}, '5', true),
    ({'min': 1}, 0, false),
    ({'max': 5}, 6, false),
    ({'min': 1}, 'viele', false),
    // one_of, any_of, not, present
    (
      {
        'one_of': ['preference', 'fact'],
      },
      'Preference',
      true,
    ),
    (
      {
        'one_of': ['preference', 'fact'],
      },
      'person',
      false,
    ),
    (
      {
        'any_of': [
          600,
          {'clock': '00:10'},
        ],
      },
      '00:10',
      true,
    ),
    (
      {
        'any_of': [600, 300],
      },
      120,
      false,
    ),
    (
      {
        'not': {'contains': 'x'},
      },
      'abc',
      true,
    ),
    (
      {
        'not': {'contains': 'x'},
      },
      'xyz',
      false,
    ),
    ({'present': true}, 'a', true),
    ({'present': false}, null, true),
    ({'present': false}, 'a', false),
    // mehrere Schlüssel = und
    ({'contains': 'Tauchen', 'matches': '^T'}, 'Tauchen', true),
    ({'contains': 'Tauchen', 'matches': '^X'}, 'Tauchen', false),
  ];

  for (final (spec, value, passes) in table) {
    test('$spec auf $value → ${passes ? 'passt' : 'passt nicht'}', () {
      final p = ValuePredicate.parse(spec);
      final why = p.check(value, time);
      expect(why == null, passes, reason: why ?? p.describe());
      if (!passes) expect(why, isNotEmpty);
    });
  }

  test('fehlende Felder', () {
    for (final spec in <Object?>[
      'x',
      {'contains': 'x'},
      {'matches': 'x'},
      {'at': '+1d 10:00'},
      {'date': '+1d'},
      {'clock': '07:00'},
      {'min': 1},
      {'present': true},
    ]) {
      final p = ValuePredicate.parse(spec);
      expect(p.check(null, time, present: false), isNotNull, reason: '$spec');
    }
    expect(
      ValuePredicate.parse({'present': false})
          .check(null, time, present: false),
      isNull,
    );
    expect(
      ValuePredicate.parse({'not': 'x'}).check(null, time, present: false),
      isNull,
    );
  });

  test('ungültige Spezifikationen', () {
    for (final bad in <Object?>[
      <String, Object?>{},
      {'bogus': 1},
      {'contains': <Object?>[]},
      {'contains': null},
      {'matches': true},
      {'at': '+1d', 'tol_min': -1},
      {'at': '+1d', 'tol_min': 'x'},
      {'clock': '25:00'},
      {'min': 'eins'},
      {'one_of': 'a'},
      {'present': 'ja'},
      {'any_of': <Object?>[]},
      {'eq': 1, 'tol_min': 3},
    ]) {
      expect(
        () => ValuePredicate.parse(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('Beschreibungen', () {
    String d(Object? s) => ValuePredicate.parse(s).describe();
    expect(d('Tauchen'), '= „Tauchen“');
    expect(d({'contains': 'a'}), 'enthält [a]');
    expect(
      d({
        'contains_any': ['a', 'b'],
      }),
      'enthält eines von [a, b]',
    );
    expect(d({'matches': 'x'}), '~ /x/');
    expect(d({'at': '+1d 10:00'}), '@ +1d 10:00');
    expect(d({'at': '+1d 10:00', 'tol_min': 5}), '@ +1d 10:00 ±5 min');
    expect(d({'date': 'sat'}), 'Datum sat');
    expect(d({'clock': '7:05'}), 'Uhrzeit 07:05');
    expect(d({'min': 1, 'max': 2}), 'in [1..2]');
    expect(d({'max': 2}), 'in [..2]');
    expect(
      d({
        'one_of': [1, 2],
      }),
      '(= 1 oder = 2)',
    );
    expect(d({'present': true}), 'vorhanden');
    expect(d({'present': false}), 'nicht vorhanden');
    expect(d({'not': 'a'}), 'nicht = „a“');
    expect(d({'contains': 'a', 'matches': 'b'}), 'enthält [a] und ~ /b/');
    expect(ValuePredicate.parse('a').toString(), '= „a“');
  });

  test('Fehlertexte nennen erwarteten Wert', () {
    expect(
      ValuePredicate.parse({'at': '+1d 10:00', 'tol_min': 5})
          .check('2026-10-15T11:00', time),
      'ist 2026-10-15T11:00, erwartet 2026-10-15T10:00 ±5 min',
    );
    expect(
      ValuePredicate.parse({'at': '+1d 10:00'}).check('2026-10-15', time),
      contains('ohne Uhrzeit'),
    );
    expect(
      ValuePredicate.parse({
        'contains_any': ['a', 'b'],
      }).check('c', time),
      contains('eines von'),
    );
  });

  test('contains ignoriert Akzente (Review #10)', () {
    final p = ValuePredicate.parse({'contains': 'plongee'});
    expect(p.check('Plongée', time), isNull);
    expect(
      ValuePredicate.parse({'contains': 'Plongée'})
          .check('PLONGEE demain', time),
      isNull,
    );
    expect(
      ValuePredicate.parse({'contains': 'uber'}).check('Über', time),
      isNull,
    );
    expect(
      ValuePredicate.parse({
        'contains': ['soeur'],
      }).check(['ma sœur'], time),
      isNull,
    );
    expect(foldAccents('Ça Être Œuf Straße'), 'ca etre oeuf straße');
  });

  test('looseEquals', () {
    expect(looseEquals(null, null), isTrue);
    expect(looseEquals('1', '01'), isFalse);
    expect(looseEquals(1, true), isFalse);
  });
}
