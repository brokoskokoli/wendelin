import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  final table = <String, bool>{
    // gültig
    'calendar__create_event': true,
    'a': true,
    'A': true,
    '0': true,
    '_': true,
    '-': true,
    'web__fetch-v2': true,
    'Tool_123': true,
    'a' * 64: true,
    // ungültig
    '': false,
    'a' * 65: false,
    'calendar.create': false,
    'calendar create': false,
    ' calendar': false,
    'calendar ': false,
    'calendar\n': false,
    'tab\tname': false,
    'kalender__ändern': false,
    'a/b': false,
    'a:b': false,
    'emoji🙂': false,
  };

  for (final MapEntry(key: name, value: valid) in table.entries) {
    final label = name.length > 20 ? '${name.length} Zeichen' : '"$name"';
    test('$label → $valid', () {
      expect(isValidToolName(name), valid);
      expect(Tool.isValidToolName(name), valid);
    });
  }
}
