import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

void main() {
  // Semantik von foldForMatch (WP36 M3): eine Zeile je Regel.
  group('foldForMatch', () {
    for (final (input, expected, rule) in [
      ('Wendelin', 'wendelin', 'Kleinschreibung'),
      ('Äpfel Öl Übung', 'apfel ol ubung', 'Umlaute'),
      ('Café crème à côté', 'cafe creme a cote', 'Akzente (fr)'),
      ('Ça, niño', 'ca nino', 'Cedille, Tilde'),
      ('Größe', 'grosse', 'ß → ss'),
      ('Œuvre', 'oeuvre', 'œ → oe'),
      ('Æble', 'aeble', 'æ → ae'),
      ('Øresund', 'oresund', 'ø → o'),
      ('Wendelin-Test', 'wendelin test', 'Bindestrich trennt'),
      ('Mein_Urlaub', 'mein urlaub', 'Unterstrich trennt'),
      ('  Urlaub \t Ideen \n', 'urlaub ideen', 'Leerraum zusammengefasst'),
      ('Was?! Ja… (gut)', 'was ja gut', 'Satzzeichen'),
      ('Notiz 2026', 'notiz 2026', 'Ziffern bleiben'),
      ('Москва', 'москва', 'andere Schriften bleiben'),
      ('aujourd’hui', 'aujourd hui', 'Apostroph trennt'),
      ('', '', 'leer'),
      ('—', '', 'nur Zeichen'),
    ]) {
      test('$rule: „$input“', () => expect(foldForMatch(input), expected));
    }
  });

  group('foldForMatch basicOnly (Listen, Obsidian)', () {
    for (final (input, expected) in [
      ('Äpfel Größe Café', 'apfel grosse cafe'),
      ('Æble', 'æble'),
      ('Øresund', 'øresund'),
      ('Œuvre', 'œuvre'),
      ('Ångström', 'ångstrom'),
      ('Ýmir ÿ', 'ýmir ÿ'),
      ('Wendelin-Test', 'wendelin test'),
    ]) {
      test('$input → $expected', () {
        expect(foldForMatch(input, basicOnly: true), expected);
      });
    }
    test('ý folds in the full variant', () {
      expect(foldForMatch('Ýmir'), 'ymir');
    });
  });

  group('foldLetter', () {
    for (final (input, expected) in [
      ('ä', 'a'),
      ('ß', 'ss'),
      ('æ', 'ae'),
      ('ø', 'o'),
      ('ý', 'y'),
      ('x', 'x'),
    ]) {
      test('$input → $expected', () => expect(foldLetter(input), expected));
    }
  });

  group('foldFlat', () {
    for (final (input, expected) in [
      ('Wendelin-Test', 'wendelintest'),
      ('Wandel Intest', 'wandelintest'),
      ('Größe_Ärger', 'grossearger'),
      ('Notiz 2026', 'notiz2026'),
      ('  ', ''),
    ]) {
      test('$input → $expected', () => expect(foldFlat(input), expected));
    }
  });
}
