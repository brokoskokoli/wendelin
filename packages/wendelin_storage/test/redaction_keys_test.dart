// WP155: Schlüssel pin/otp/code/state in JSON und Query-Parametern.
import 'package:test/test.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

void main() {
  group('JSON', () {
    for (final (key, value) in [
      ('pin', '1234'),
      ('PIN', 1234),
      ('otp', 123456),
      ('code', 'AB12'),
      ('code', 424242),
      ('code', 1234),
      ('user_pin', '9999'),
      ('otpCode', '123456'),
      ('state', 'xyzXYZ1234567890'),
    ]) {
      test('$key=$value wird ersetzt', () {
        final out = redactSecrets({key: value, 'note': 'ok'})! as Map;
        expect(out[key], redactedValue);
        expect(out['note'], 'ok');
      });
    }

    test('code: Zahl erst ab 4 Stellen, Text immer', () {
      expect(redactSecrets({'code': 999}), {'code': 999});
      expect(redactSecrets({'code': 1000}), {'code': redactedValue});
      expect(redactSecrets({'code': -12345}), {'code': redactedValue});
      expect(redactSecrets({'code': '404'}), {'code': redactedValue});
      expect(redactSecrets({'code': true}), {'code': true});
    });

    test('verschachtelt und in Listen', () {
      final out =
          redactSecrets({
                'args': [
                  {
                    'inner': {'pin': '1234'},
                  },
                ],
              })!
              as Map;
      expect('$out', isNot(contains('1234')));
    });

    test('Gerätezustand und verwandte Felder bleiben lesbar', () {
      final out =
          redactSecrets({
                'state': 'on',
                'status_code': 200,
                'code': 404,
                'code2': 500.0,
                'country_code': 'DE',
                'pinned': true,
                'spinner': 'x',
              })!
              as Map;
      expect(out, {
        'state': 'on',
        'status_code': 200,
        'code': 404,
        'code2': 500.0,
        'country_code': 'DE',
        'pinned': true,
        'spinner': 'x',
      });
    });

    test('Name/Wert-Paar mit state bleibt, mit pin wird ersetzt', () {
      expect(redactSecrets({'name': 'state', 'value': 'on'}), {
        'name': 'state',
        'value': 'on',
      });
      expect(redactSecrets({'name': 'pin', 'value': '1234'}), {
        'name': 'pin',
        'value': redactedValue,
      });
    });
  });

  group('Query', () {
    test('OAuth-Rückruf: code und state', () {
      final out = redactSecretValues(
        'https://x.test/cb?code=AbC123xyz&state=Zq9Kq1&ok=1',
      );
      expect(out, 'https://x.test/cb?code=***&state=***&ok=1');
    });

    test('pin und otp, auch hinter &', () {
      final out = redactSecretValues('https://x.test/a?id=7&pin=1234&otp=55');
      expect(out, 'https://x.test/a?id=7&pin=***&otp=***');
    });

    test('ähnliche Namen bleiben', () {
      const url = 'https://x.test/a?country_code=DE&zipcode=12345&spin=1';
      expect(redactSecretValues(url), url);
    });
  });
}
