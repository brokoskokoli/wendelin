import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

Matcher _invalid(String part) => throwsA(
  isA<InvalidArgumentsException>().having(
    (e) => e.message,
    'message',
    contains(part),
  ),
);

void main() {
  const args = ToolArgs({
    's': '  Text ',
    'blank': '  ',
    'i': 5,
    'd': 30.0,
    'frac': 1.5,
    'b': true,
    'ls': ['a', ' b '],
    'li': [1, 2.0],
    'bad': 42,
  });

  test('Strings', () {
    expect(args.requireString('s'), 'Text');
    expect(args.optString('missing'), isNull);
    expect(() => args.requireString('blank'), _invalid('„blank“ fehlt'));
    expect(() => args.requireString('missing'), _invalid('fehlt'));
    expect(() => args.optString('bad'), _invalid('Text'));
    expect(args.has('s'), isTrue);
    expect(args.has('missing'), isFalse);
  });

  test('Zahlen', () {
    expect(args.optInt('i'), 5);
    expect(args.optInt('d'), 30);
    expect(args.optInt('missing'), isNull);
    expect(() => args.optInt('frac'), _invalid('ganze Zahl'));
    expect(() => args.optInt('s'), _invalid('ganze Zahl'));
    expect(() => args.optInt('i', min: 6), _invalid('zwischen 6'));
    expect(() => args.optInt('i', max: 4), _invalid('und 4'));
    expect(args.optInt('i', min: 5, max: 5), 5);
    expect(args.requireInt('i'), 5);
    expect(() => args.requireInt('missing'), _invalid('fehlt'));
  });

  test('Bool und Listen', () {
    expect(args.optBool('b'), isTrue);
    expect(args.optBool('missing'), isNull);
    expect(() => args.optBool('s'), _invalid('true oder false'));
    expect(args.optStringList('ls'), ['a', 'b']);
    expect(args.optStringList('missing'), isNull);
    expect(() => args.optStringList('li'), _invalid('Liste von Texten'));
    expect(args.optIntList('li'), [1, 2]);
    expect(args.optIntList('missing'), isNull);
    expect(() => args.optIntList('s'), _invalid('Liste'));
    expect(() => args.optIntList('li', max: 1), _invalid('„li[1]“'));
    expect(const InvalidArgumentsException('x').toString(), contains('x'));
  });
}
