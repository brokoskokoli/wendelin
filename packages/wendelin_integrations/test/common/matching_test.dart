import 'package:test/test.dart';
import 'package:wendelin_integrations/src/common/matching.dart';

void main() {
  // WP36 c: Listen- und Obsidian-Abgleich falten nur die Basis-Buchstaben;
  // Sonderbuchstaben bleiben stehen wie vor der Zusammenlegung.
  test('normalizeText faltet nur Basis-Buchstaben', () {
    const cases = {
      'Äpfel & Birnen': 'apfel birnen',
      'Straße': 'strasse',
      'Æble': 'æble',
      'Øresund': 'øresund',
      'Œuvre': 'œuvre',
      'Ålesund': 'ålesund',
      'São Paulo': 'são paulo',
      'Ýmir': 'ýmir',
    };
    cases.forEach((input, expected) {
      expect(normalizeText(input), expected, reason: input);
    });
  });

  test('foldText lässt Sonderbuchstaben stehen', () {
    expect(foldText('Æble'), 'æble');
    expect(foldText('Øresund'), 'øresund');
  });
}
