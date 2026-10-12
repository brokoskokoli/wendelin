import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/src/common/redactor.dart';
import 'package:wendelin_providers/wendelin_providers.dart';

void main() {
  final secrets = {'a': ' key-aaaa \n', 'b': 'key-bbbb', 'leer': '  '};
  Future<String?> read(String ref) async => secrets[ref];

  group('Credentials', () {
    test(
      'ApiKeyAuth: x-api-key bzw. Bearer, Key getrimmt und registriert',
      () async {
        final redactor = Redactor();
        expect(
          await Credentials(
            const ApiKeyAuth('a'),
            read,
            style: ApiKeyStyle.xApiKey,
          ).headers(redactor),
          {'x-api-key': 'key-aaaa'},
        );
        expect(
          await Credentials(
            const ApiKeyAuth('a'),
            read,
            style: ApiKeyStyle.bearer,
          ).headers(redactor),
          {'Authorization': 'Bearer key-aaaa'},
        );
        expect(redactor.apply('x key-aaaa'), 'x ***');
      },
    );

    test('eigener Header-Name', () async {
      expect(
        await Credentials(
          const ApiKeyAuth('a', headerName: 'api-key'),
          read,
          style: ApiKeyStyle.bearer,
        ).headers(Redactor()),
        {'api-key': 'key-aaaa'},
      );
      expect(
        await Credentials(
          const ApiKeyAuth('a', headerName: 'authorization'),
          read,
          style: ApiKeyStyle.xApiKey,
        ).headers(Redactor()),
        {'authorization': 'Bearer key-aaaa'},
      );
    });

    test('NoAuth und CustomHeaders', () async {
      expect(await Credentials.none().headers(Redactor()), isEmpty);
      final redactor = Redactor();
      expect(
        await Credentials(
          CustomHeadersAuth({'X-One': 'a', 'X-Two': 'b'}),
          read,
          style: ApiKeyStyle.bearer,
        ).headers(redactor),
        {'X-One': 'key-aaaa', 'X-Two': 'key-bbbb'},
      );
      expect(redactor.apply('key-bbbb'), '***');
    });

    test('fehlender oder leerer Key → AuthException mit Referenz', () async {
      for (final ref in ['fehlt', 'leer']) {
        await expectLater(
          Credentials(
            ApiKeyAuth(ref),
            read,
            style: ApiKeyStyle.bearer,
          ).headers(Redactor()),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              contains(ref),
            ),
          ),
        );
      }
    });

    test('OAuth/PKCE noch nicht unterstützt', () async {
      await expectLater(
        Credentials(
          OAuthPkceAuth(
            clientId: 'c',
            authorizationUrl: 'https://a',
            tokenUrl: 'https://t',
            tokenSecretRef: 't',
          ),
          read,
          style: ApiKeyStyle.bearer,
        ).headers(Redactor()),
        throwsA(isA<AuthException>()),
      );
    });

    test('Credentials.apiKey und toString ohne Key', () async {
      final c = Credentials.apiKey('geheim-123', style: ApiKeyStyle.xApiKey);
      expect(await c.headers(Redactor()), {'x-api-key': 'geheim-123'});
      expect(c.toString(), isNot(contains('geheim-123')));
    });
  });
}
