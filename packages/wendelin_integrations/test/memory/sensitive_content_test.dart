import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  const rejected = <String, String>{
    'Visa mit Leerzeichen': '4111 1111 1111 1111',
    'Mastercard mit Bindestrichen': 'Karte 5555-5555-5555-4444 bitte merken',
    'Amex 15 Stellen': '378282246310005',
    'IBAN kompakt': 'DE89370400440532013000',
    'IBAN gruppiert': 'Konto: DE89 3704 0044 0532 0130 00',
    'IBAN Österreich klein': 'at611904300234573201',
    'Passwort ist': 'Mein Passwort ist Sommer2026',
    'password is': 'my password is hunter2',
    'Kennwort Doppelpunkt': 'Kennwort: abc',
    'PIN': 'Die PIN lautet 1234',
    'PIN Doppelpunkt': 'PIN: 4711',
    'API-Key': 'API-Key = abcdef',
    'Token': 'Token: xyz',
    'Schlüssel-Muster': 'nimm sk-abcdefghijklmnopqrstuv',
  };
  rejected.forEach((label, text) {
    test('abgewiesen: $label', () {
      expect(sensitiveContentReason(text), isNotNull);
    });
  });

  const allowed = <String, String>{
    'Vorliebe': 'Mag keinen Koriander',
    'Telefonnummer kurz': 'Anna: 0170 1234567',
    'Nicht-Luhn 16 Stellen': '4111 1111 1111 1112',
    'Jahreszahlen': 'Geboren 1990, verheiratet seit 2015',
    'Wort Passwort ohne Wert': 'Erinnere mich, das Passwort zu ändern.',
    'PIN-Code Wort': 'Pinguine mag sie sehr',
    'Kurze Zahl': 'Hausnummer 42',
  };
  allowed.forEach((label, text) {
    test('erlaubt: $label', () {
      expect(sensitiveContentReason(text), isNull);
    });
  });

  test('Begründungen sind deutsch und unterscheiden die Art', () {
    expect(
      sensitiveContentReason('4111111111111111'),
      contains('Kartennummern'),
    );
    expect(sensitiveContentReason('DE89370400440532013000'), contains('IBAN'));
    expect(sensitiveContentReason('PIN: 1'), contains('PINs'));
  });
}
