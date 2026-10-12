import 'package:test/test.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

void main() {
  group('luhnValid', () {
    for (final (digits, valid) in [
      ('4111111111111111', true), // Visa-Testnummer
      ('5555555555554444', true), // Mastercard-Testnummer
      ('378282246310005', true), // Amex-Testnummer (15)
      ('79927398713', true), // Lehrbuchbeispiel
      ('4111111111111112', false),
      ('5555555555554445', false),
      ('79927398710', false),
      ('0', true),
    ]) {
      test('$digits → $valid', () => expect(luhnValid(digits), valid));
    }
  });

  group('detectSensitiveContent', () {
    const card = SensitiveKind.cardNumber;
    const iban = SensitiveKind.iban;
    const cred = SensitiveKind.credential;
    for (final (text, expected) in <(String, SensitiveKind?)>[
      // Kartennummern: Luhn-gültig
      ('Karte 4111111111111111', card),
      ('Karte 4111 1111 1111 1111 bitte merken', card),
      ('5555-5555-5555-4444', card),
      ('Amex 3782 822463 10005', card),
      ('4111111111111111 und 12 Äpfel', card),
      ('Nummer: 12 4111 1111 1111 1111', card),
      // Luhn-ungültig oder zu kurz/lang
      ('Karte 4111 1111 1111 1112', null),
      ('Bestellnummer 4111111111111112', null),
      ('Telefon +49 170 1234567', null),
      ('Termin am 2026-10-13 um 10:00', null),
      ('Seriennummer 41111111111111110000000', null),
      ('411111111117', null), // 12 Ziffern, Luhn-gültig
      ('41111111111111111115', null), // 20 Ziffern, Luhn-gültig
      ('4111111111111111110 5', card), // 19 Ziffern, Luhn-gültig
      // IBAN
      ('Konto DE89 3704 0044 0532 0130 00', iban),
      ('IBAN: DE89370400440532013000', iban),
      ('FR1420041010050500013M02606', iban),
      ('GB29 NWBK 6016 1331 9268 19', iban),
      ('de89 3704 0044 0532 0130 00', null), // Ländercode klein
      ('Code AB12CDEFGHIJKLMN', null), // zu wenige Ziffern
      ('XY12 AB12 34CD 56EF', iban), // genau 6 Ziffern im BBAN
      ('XY12 AB12 34CD 5xEF', null), // 5 Ziffern
      ('DE89 1234 5678 901', iban), // 11 Zeichen BBAN
      ('DE89 1234 5678 90', null), // 10 Zeichen BBAN
      ('Flug LH12 nach Bali', null),
      // Zugangsdaten
      ('Passwort: hund123', cred),
      ('mein passwort ist hund123', cred),
      ('Das WLAN-Kennwort lautet Sonne2026', cred),
      ('password=abc', cred),
      ('Die PIN ist 4711', cred),
      ('PIN-Code: 0815', cred),
      ('Geheimzahl: 1234', cred),
      ('Zugangsdaten: user / pw', cred),
      ('Passwörter: a, b', cred),
      ('Ich muss mein Passwort ändern', null),
      ('Pinguine sind toll: ja', null),
      ('Die Pinnwand ist voll', null),
      ('Anna ist meine Schwester', null),
      ('', null),
    ]) {
      test('"$text" → $expected', () {
        expect(detectSensitiveContent(text), expected);
      });
    }
  });

  test('checkNotSensitive wirft mit deutscher Meldung ohne den Inhalt', () {
    expect(() => checkNotSensitive('ok'), returnsNormally);
    for (final (text, kind) in [
      ('4111111111111111', SensitiveKind.cardNumber),
      ('DE89370400440532013000', SensitiveKind.iban),
      ('PIN: 4711', SensitiveKind.credential),
    ]) {
      try {
        checkNotSensitive(text);
        fail('keine Exception für $text');
      } on SensitiveContentException catch (e) {
        expect(e.kind, kind);
        expect(e.message, contains('nicht gespeichert'));
        expect(e.toString(), isNot(contains(text)));
        expect(e.toString(), contains(kind.name));
      }
    }
  });
}
