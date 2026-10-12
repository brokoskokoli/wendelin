import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// All detection cases from wendelin_storage (WP04) and
/// wendelin_integrations (WP06), plus the false positives from the WP04
/// re-review (WP13).
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
      // --- Kartennummern: Luhn-gültig
      ('Karte 4111111111111111', card),
      ('4111 1111 1111 1111', card),
      ('Karte 4111 1111 1111 1111 bitte merken', card),
      ('5555-5555-5555-4444', card),
      ('Karte 5555-5555-5555-4444 bitte merken', card),
      ('378282246310005', card), // Amex 15 Stellen
      ('Amex 3782 822463 10005', card),
      ('4111111111111111 und 12 Äpfel', card),
      ('Nummer: 12 4111 1111 1111 1111', card),
      ('4111.1111.1111.1111', card), // Punkte
      ('4111  1111  1111  1111', card), // mehrfache Leerzeichen
      ('0111111111111111 4111111111111111', card), // zweite Gruppe zählt
      ('4111111111111111110 5', card), // 19 Ziffern
      ('Visa alt 4222222222222', card), // 13 Ziffern, beginnt mit 42
      ('49170123456703', card), // 14 Ziffern ab 49 ist keine Telefonnummer
      // --- keine Kartennummer
      ('Karte 4111 1111 1111 1112', null), // Luhn-ungültig
      ('Bestellnummer 4111111111111112', null),
      ('Nicht-Luhn 4111 1111 1111 1112', null),
      ('Nummer 8111111111111112', null), // Luhn-gültig, beginnt mit 8
      ('Kundennummer 0111111111111119', null), // Luhn-gültig, führende 0
      ('Mitglied 1111111111111117', null), // Luhn-gültig, führende 1
      ('Telefon +49 170 1234567', null),
      ('Telefon +49 4111 1111 1111 1111', null), // mit + ignoriert
      ('Telefon + 4111111111111111', null),
      ('Ruf an: 4917012345675', null), // 13 Ziffern ab 49, Luhn-gültig
      ('Wien 4312345678903', null), // 13 Ziffern ab 43, Luhn-gültig
      ('Anna: 0170 1234567', null),
      ('Termin am 13.10.2026 um 10.30', null),
      ('Termin am 2026-10-13 um 10:00', null),
      ('Seriennummer 41111111111111110000000', null), // > 19 Ziffern
      ('411111111117', null), // 12 Ziffern, Luhn-gültig
      ('41111111111111111115', null), // 20 Ziffern, Luhn-gültig
      ('Geboren 1990, verheiratet seit 2015', null),
      ('Hausnummer 42', null),
      // --- IBAN
      ('Konto DE89 3704 0044 0532 0130 00', iban),
      ('Konto: DE89 3704 0044 0532 0130 00', iban),
      ('IBAN: DE89370400440532013000', iban),
      ('DE89370400440532013000', iban),
      ('FR1420041010050500013M02606', iban),
      ('GB29 NWBK 6016 1331 9268 19', iban),
      ('de89 3704 0044 0532 0130 00', iban), // Ländercode klein
      ('at611904300234573201', iban), // Österreich, klein, kompakt
      ('DE89  3704  0044  0532  0130  00', iban), // doppelte Leerzeichen
      ('DE89 37040044 0532013000', iban), // gemischt, mod-97 gültig
      ('DE89 370400440532013000', iban),
      ('DE8937040044 0532 0130 00', iban),
      ('DE89-3704-0044-0532-0130-00', iban),
      ('IBAN: GB29-NWBK-6016-1331-9268-19.', iban),
      ('NO9386011117947', iban), // Norwegen: 11 Zeichen BBAN, mod-97
      ('NO93 8601 1117 947', iban),
      ('BE68 5390 0754 7034', iban), // 12 Zeichen BBAN, mod-97
      ('DE88 3704 0044 0532 0130 00', iban), // vertippt, 18 Zeichen BBAN
      ('XY12 AB12 34CD 56EF 7890', iban), // 16 Zeichen BBAN, ohne mod-97
      ('XY12 AB12 34CD 56EF 789', iban), // genau 15 Zeichen, ohne mod-97
      ('XY12 AB12 34CD 56EF 78', null), // 14 Zeichen, mod-97 ungültig
      // --- keine IBAN
      ('Raum12 3456 7890 1234', null), // mitten im Wort
      ('Code AB12CDEFGHIJKLMN', null), // zu wenige Ziffern
      ('XY12 AB1x 34CD 5xEF yXYZ', null), // 4 Ziffern
      ('XY12 AB12 34CD 56EF', null), // 12 Zeichen BBAN, mod-97 ungültig
      ('Bestellnummer AB12 3456 7890 1234', null),
      ('DE88-3704-0044-0532-0130-00', null), // Bindestriche, mod-97 falsch
      ('DE88 37040044 0532013000', null), // gemischt, mod-97 falsch
      ('NO9486011117947', null), // 11 Zeichen, mod-97 falsch
      ('DE89 1234 5678 90', null), // 10 Zeichen BBAN
      ('Flug LH12 nach Bali', null),
      ('Flug LH12 um 14 Uhr 30 Gate 22 Sitz 14', null),
      ('Zug ICE12 3456 Wagen 7', null),
      // --- Zugangsdaten
      ('Passwort: hund123', cred),
      ('mein passwort ist hund123', cred),
      ('Mein Passwort ist Sommer2026', cred),
      ('Das WLAN-Kennwort lautet Sonne2026', cred),
      ('Kennwort: abc', cred),
      ('password=abc', cred),
      ('my password is hunter2', cred),
      ('The wifi password was Summer2026', cred),
      ('Die PIN ist 4711', cred),
      ('Die PIN lautet 1234', cred),
      ('PIN: 4711', cred),
      ('PIN-Code: 0815', cred),
      ('Pin-Nummer: 0000', cred),
      ('PIN 1234', cred),
      ('PUK: 12345678', cred),
      ('TAN ist 123456', cred),
      ('Geheimzahl: 1234', cred),
      ('Zugangsdaten: user / pw', cred),
      ('Passwörter: a, b', cred),
      ('passwd = x', cred),
      ('API-Key = abcdef', cred),
      ('api key: abcdef', cred),
      ('Token: xyz', cred),
      ('Secret: abc', cred),
      ('Das Token für GitHub = abc', cred),
      ('CVV 123', cred),
      ('CVC: 456', cred),
      ('Sicherheitscode: 789', cred),
      ('Die Kartenprüfnummer ist 321', cred),
      ('Prüfnummer 999', cred),
      ('Das Passwort für das WLAN ist hunter2', cred),
      ('Die PIN meiner Bankkarte ist 1234', cred),
      ('Passwort hunter2', cred),
      ('Das WLAN-Passwort heißt Sonnenschein', cred),
      ('Passwort vergessen hat sie heute ist Montag', cred), // 4 Wörter
      // API-Key-Muster
      ('nimm sk-abcdefghijklmnopqrstuv', cred),
      ('pk_live_abcdefghijklmnop1234', cred),
      (
        'ghp_'
            'abcdefghijklmnopqrstuvwxyz0123',
        cred,
      ), // geteilt für check_secrets
      ('xoxb-1234567890-abcdefghijkl', cred),
      ('tvly-abcdefghijklmnop', cred),
      ('AKIAIOSFODNN7EXAMPLE', cred),
      // --- keine Zugangsdaten
      ('Ich muss mein Passwort ändern', null),
      ('Das Token ist abgelaufen', null),
      ('Das Secret ist, dass ich Kuchen mag', null),
      ('Die Tan ist am Strand gut geworden', null),
      ('Der Sicherheitscode ist auf der Rückseite', null),
      ('Frag nach dem CVV', null),
      ('Erinnere mich, das Passwort zu ändern.', null),
      ('Erinnere mich an die PIN-Änderung', null),
      ('Passwort-Änderung ist am Montag fällig', null),
      ('Passwort vergessen hat sie gestern abend ist Montag', null), // 5
      ('Passwort vergessen, bitte zurücksetzen', null),
      ('Pinguine sind toll: ja', null),
      ('Pinguine mag sie sehr', null),
      ('Die Pinnwand ist voll', null),
      ('Skandinavienrundreise im Sommer', null),
      ('wir planen eine skandinavienrundreise', null), // sk + 19 Buchstaben
      ('sk-kurz', null),
      ('Mag keinen Koriander', null),
      ('Anna ist meine Schwester', null),
      ('', null),
    ]) {
      test('"$text" → ${expected?.name}', () {
        expect(detectSensitiveContent(text)?.kind, expected);
      });
    }
  });

  group('ibanChecksumValid', () {
    for (final (iban, valid) in [
      ('DE89370400440532013000', true),
      ('de89370400440532013000', true),
      ('GB29NWBK60161331926819', true),
      ('NO9386011117947', true),
      ('DE88370400440532013000', false),
      ('DE89370400440532013001', false),
      ('DE8937040044053201300!', false),
    ]) {
      test('$iban → $valid', () => expect(ibanChecksumValid(iban), valid));
    }
  });

  test('Begründungen sind deutsch, je Art verschieden, ohne den Inhalt', () {
    final reasons = {for (final k in SensitiveKind.values) k: k.reason};
    expect(reasons.values.toSet(), hasLength(3));
    expect(reasons[SensitiveKind.cardNumber], contains('Kartennummern'));
    expect(reasons[SensitiveKind.iban], contains('IBAN'));
    expect(reasons[SensitiveKind.credential], contains('PINs'));
    for (final r in reasons.values) {
      expect(r, contains('nicht gespeichert'));
    }
    final f = detectSensitiveContent('PIN: 4711')!;
    expect(f.reason, SensitiveKind.credential.reason);
    expect(f.reason, isNot(contains('4711')));
    expect(f.toString(), 'SensitiveFinding(credential)');
    expect(f, const SensitiveFinding(SensitiveKind.credential));
    expect(
      f.hashCode,
      const SensitiveFinding(SensitiveKind.credential).hashCode,
    );
    expect(f, isNot(const SensitiveFinding(SensitiveKind.iban)));
  });
}
