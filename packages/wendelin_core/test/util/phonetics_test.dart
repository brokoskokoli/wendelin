import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  group('foldFlat', () {
    for (final (input, expected) in [
      ('Wendelin-Test', 'wendelintest'),
      ('Wandel Intest', 'wandelintest'),
      ('Größe_Ärger', 'grossearger'),
      ('Café crème', 'cafecreme'),
      ('Œuvre', 'oeuvre'),
      ('Notiz 2026', 'notiz2026'),
      ('  ', ''),
    ]) {
      test('$input → $expected', () => expect(foldFlat(input), expected));
    }
  });

  group('colognePhonetic', () {
    for (final (input, expected) in [
      // Lehrbuchbeispiel der Kölner Phonetik.
      ('Müller-Lüdenscheidt', '65752682'),
      ('Wikipedia', '3412'),
      ('Breschnew', '17863'),
      ('Wendelin-Test', '36256282'),
      ('Wandel Intest', '36256282'),
      ('Wendeline Test', '36256282'),
      ('Vendelin', '36256'),
      // C am Anfang: vor A/H/K/L/O/Q/R/U/X → 4, sonst 8.
      ('Christian', '47826'),
      ('Celle', '85'),
      // C im Wort: nach S/Z immer 8, vor A/H/K/O/Q/U/X → 4.
      ('Schach', '84'),
      ('Ecke', '04'),
      ('Ac', '08'),
      // D/T vor C/S/Z → 8; X nach C/K/Q → 8, sonst 48.
      ('Stadtzentrum', '82286276'),
      ('Max', '648'),
      ('Hexe', '048'),
      ('Dachs', '248'),
      ('Pharao', '37'),
      ('Ypsilon', '01856'),
      ('Raum 12', '7612'),
      ('', ''),
    ]) {
      test(
        '$input → $expected',
        () => expect(colognePhonetic(input), expected),
      );
    }
  });

  group('simplePhonetic', () {
    for (final (input, expected) in [
      ('Robert', '6163'),
      ('Rupert', '6163'),
      ('Philippe', '141'),
      ('Ashcraft', '02613'),
      ('Courses', '2622'),
      ('Liste 3', '4233'),
    ]) {
      test('$input → $expected', () => expect(simplePhonetic(input), expected));
    }
    test('Wendelin-Test und Wandel Intest gleich', () {
      expect(simplePhonetic('Wandel Intest'), simplePhonetic('Wendelin-Test'));
    });
  });

  test('phoneticKey wählt nach Sprache', () {
    expect(phoneticKey('Robert'), colognePhonetic('Robert'));
    expect(phoneticKey('Robert', language: 'de'), colognePhonetic('Robert'));
    expect(phoneticKey('Robert', language: 'fr'), simplePhonetic('Robert'));
    expect(phoneticKey('Robert', language: 'en'), simplePhonetic('Robert'));
  });

  group('editDistance', () {
    for (final (a, b, d) in [
      ('', '', 0),
      ('abc', '', 3),
      ('', 'ab', 2),
      ('kitten', 'sitting', 3),
      ('wandelintest', 'wendelintest', 1),
      ('wendelinetest', 'wendelintest', 1),
      ('flaw', 'lawn', 2),
      ('same', 'same', 0),
    ]) {
      test('$a/$b → $d', () {
        expect(editDistance(a, b), d);
        expect(editDistance(b, a), d);
      });
    }
  });
}
