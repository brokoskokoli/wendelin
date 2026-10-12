import 'package:test/test.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

void main() {
  final cases = <(String, String, String)>[
    ('nur erste Zeile', 'a\n#0 stack', 'a'),
    (
      'Query und Fragment entfernt',
      'GET https://x.de/a/b?api_key=1&q=2#frag failed',
      'GET https://x.de/a/b failed',
    ),
    ('Userinfo entfernt', 'ftp://u:p@host/x', 'ftp://host/x'),
    ('key=value maskiert', 'token=abc123 rest', 'token=*** rest'),
    ('JSON-Feld maskiert', '{"api_key": "abc"}', '{"api_key": "***"}'),
    ('Passwort-Doppelpunkt', 'password: geheim', 'password: ***'),
    (
      'Bearer maskiert',
      'Authorization: Bearer abc.def',
      'Authorization: Bearer ***',
    ),
    ('Bearer allein', 'got Bearer abc.def', 'got Bearer ***'),
    (
      'harmlos bleibt',
      'Kalender nicht erreichbar',
      'Kalender nicht erreichbar',
    ),
  ];
  for (final (name, input, expected) in cases) {
    test(name, () => expect(sanitizeErrorText(input), expected));
  }

  test('kürzt auf maxLength', () {
    final t = sanitizeErrorText('x' * 50, maxLength: 10);
    expect(t, '${'x' * 9}…');
    expect(sanitizeErrorText('x' * 10, maxLength: 10), 'x' * 10);
  });
}
