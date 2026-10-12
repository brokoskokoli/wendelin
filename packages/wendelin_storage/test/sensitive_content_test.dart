import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Detection itself is tested in wendelin_core; here only its use.
void main() {
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
        expect(e.message, kind.reason);
        expect(e.toString(), isNot(contains(text)));
        expect(e.toString(), contains(kind.name));
      }
    }
  });
}
