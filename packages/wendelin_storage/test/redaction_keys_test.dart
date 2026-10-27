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
      ('otp_code', 123),
      ('otpCode', 123),
      ('authorization_code', 123),
      ('state', 'xyzXYZ1234567890'),
      ('tan', '123456'),
      ('TAN', 123456),
      ('verification_code', '123456'),
      ('auth_code', 'AB12CD'),
      ('sms_code', 482913),
      ('smsCode', '4829'),
      ('security-code', '1234'),
      ('authcode', 'x'),
      ('login_code', 'x1'),
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

    test('Schlüssel mit Query-Geheimnis im JSON-String bleibt geschwärzt', () {
      final out = redactSecrets({'a': '{"x":"y","u?token=SECRET":1}'});
      expect('$out', isNot(contains('SECRET')));
    });

    test('10 000 verschachtelte [ im String: Rückfall auf die Regex', () {
      final deep = '${'[' * 10000}"u?token=SECRET"${']' * 10000}';
      final out = redactSecrets({'a': deep}) as Map;
      expect(out['a'], isNot(contains('SECRET')));
    });

    test('JSON als String in einem Feld wird geschwärzt', () {
      final out =
          redactSecrets({
                'args': '{"pin":"1234","note":"ok"}',
                'list': '[{"otp_code":123}]',
                'twice': '{"body":"{\\"pin\\":\\"5678\\"}"}',
                'plain': '{kein json',
                'fine': '{"a":1}',
              })!
              as Map;
      expect(out['args'], '{"pin":"***","note":"ok"}');
      expect(out['list'], '[{"otp_code":"***"}]');
      expect(out['twice'], isNot(contains('5678')));
      expect(out['plain'], '{kein json');
      expect(out['fine'], '{"a":1}');
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

    test('HTTP-Status und Länder-/Fehlercodes bleiben lesbar', () {
      final json = {
        'status_code': 401,
        'http_status_code': 'Unauthorized',
        'responseCode': 'OK',
        'http_code': 404,
        'error_code': 'E_TIMEOUT',
        'country_code': 'DE',
        'zip_code': 12345,
        'language_code': 'de',
        'color_code': '#fff',
        'tangent': 1,
        'distance': 4,
      };
      expect(redactSecrets(json), json);
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

    test('tan, verification_code, auth_code, sms_code', () {
      expect(
        redactSecretValues(
          'https://x.test/a?tan=123456&verification_code=99&ok=1'
          '&auth_code=A&sms_code=B&Security-Code=C',
        ),
        'https://x.test/a?tan=***&verification_code=***&ok=1'
        '&auth_code=***&sms_code=***&Security-Code=***',
      );
    });

    test('Fragment (#code=, #access_token=)', () {
      expect(
        redactSecretValues('https://x.test/cb#access_token=ya29.AbC&ok=1'),
        'https://x.test/cb#access_token=***&ok=1',
      );
      expect(
        redactSecretValues('https://x.test/cb#code=AbC123&state=Zq9'),
        'https://x.test/cb#code=***&state=***',
      );
    });

    test('URL-kodierte Query im Wert eines anderen Parameters', () {
      expect(
        redactSecretValues(
          'https://x.test/login?redirect_uri='
          'https%3A%2F%2Fapp.test%2Fcb%3Fcode%3DAbC123%26ok%3D1%26'
          'verification_code%3D777%26state%3DZq9',
        ),
        'https://x.test/login?redirect_uri='
        'https%3A%2F%2Fapp.test%2Fcb%3Fcode%3D***%26ok%3D1%26'
        'verification_code%3D***%26state%3D***',
      );
    });

    test('Status und ähnliche Namen in der Query bleiben', () {
      const url =
          'https://x.test/a?status_code=401&http_code=404&error_code=E1'
          '#country_code=DE';
      expect(redactSecretValues(url), url);
      const enc = 'https%3A%2F%2Fx.test%2Fa%3Fstatus_code%3D401%26ok%3D1';
      expect(redactSecretValues(enc), enc);
    });

    test('ähnliche Namen bleiben', () {
      const url = 'https://x.test/a?country_code=DE&zipcode=12345&spin=1';
      expect(redactSecretValues(url), url);
    });
  });
}
