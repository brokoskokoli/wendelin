import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

Map<String, Object?> viaString(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  final auths = <String, AuthMethod>{
    'apiKey': const ApiKeyAuth('provider.claude.key'),
    'apiKey with header': const ApiKeyAuth('k', headerName: 'x-api-key'),
    'none': const NoAuth(),
    'customHeaders': CustomHeadersAuth({
      'X-Token': 'secret.a',
      'X-Org': 'secret.b',
    }),
    'oauthPkce': OAuthPkceAuth(
      clientId: 'wendelin',
      authorizationUrl: 'https://example.org/auth',
      tokenUrl: 'https://example.org/token',
      scopes: ['openid', 'models'],
      tokenSecretRef: 'provider.or.token',
    ),
  };

  group('AuthMethod JSON round trip', () {
    auths.forEach((name, auth) {
      test(name, () {
        final decoded = AuthMethod.fromJson(viaString(auth.toJson()));
        expect(decoded, auth);
        expect(decoded.hashCode, auth.hashCode);
        expect(decoded.toString(), isNotEmpty);
      });
    });
  });

  group('AuthMethod.secretRefs', () {
    test('per kind', () {
      expect(const ApiKeyAuth('a').secretRefs, {'a'});
      expect(const NoAuth().secretRefs, isEmpty);
      expect(CustomHeadersAuth({'H1': 'a', 'H2': 'b'}).secretRefs, {'a', 'b'});
      expect((auths['oauthPkce']! as OAuthPkceAuth).secretRefs, {
        'provider.or.token',
      });
    });
  });

  group('AuthMethod equality distinguishes fields', () {
    test('apiKey', () {
      expect(const ApiKeyAuth('a'), isNot(const ApiKeyAuth('b')));
      expect(
        const ApiKeyAuth('a'),
        isNot(const ApiKeyAuth('a', headerName: 'h')),
      );
      expect(const ApiKeyAuth('a'), isNot(const NoAuth()));
    });
    test('customHeaders', () {
      expect(
        CustomHeadersAuth({'H': 'a'}),
        isNot(CustomHeadersAuth({'H': 'b'})),
      );
      expect(
        CustomHeadersAuth({'H': 'a'}),
        isNot(CustomHeadersAuth({'G': 'a'})),
      );
    });
    test('oauth', () {
      OAuthPkceAuth o({
        String clientId = 'c',
        String auth = 'a',
        String token = 't',
        String ref = 'r',
        List<String> scopes = const ['s'],
      }) => OAuthPkceAuth(
        clientId: clientId,
        authorizationUrl: auth,
        tokenUrl: token,
        tokenSecretRef: ref,
        scopes: scopes,
      );
      expect(o(), o());
      expect(o(), isNot(o(clientId: 'x')));
      expect(o(), isNot(o(auth: 'x')));
      expect(o(), isNot(o(token: 'x')));
      expect(o(), isNot(o(ref: 'x')));
      expect(o(), isNot(o(scopes: ['x'])));
    });
  });

  group('AuthMethod.fromJson rejects bad input', () {
    final cases = <String, Map<String, Object?>>{
      'unknown kind': {'kind': 'magic'},
      'missing kind': <String, Object?>{},
      'apiKey without ref': {'kind': 'apiKey'},
      'customHeaders value not string': {
        'kind': 'customHeaders',
        'secretRefs': {'H': 1},
      },
      'customHeaders not map': {'kind': 'customHeaders', 'secretRefs': 'x'},
      'oauth scope not string': {
        'kind': 'oauthPkce',
        'clientId': 'c',
        'authorizationUrl': 'a',
        'tokenUrl': 't',
        'scopes': [1],
        'tokenSecretRef': 'r',
      },
    };
    cases.forEach((name, json) {
      test(name, () {
        expect(() => AuthMethod.fromJson(json), throwsFormatException);
      });
    });
  });

  final full = ProviderProfile(
    id: 'p1',
    name: 'Claude API',
    type: ProviderType.anthropic,
    baseUrl: 'https://api.anthropic.com',
    defaultModel: 'claude-haiku',
    privacy: PrivacyLevel.standard,
    authMethod: const ApiKeyAuth('provider.p1.key'),
    budgetMonthly: 5000000,
    warnThreshold: 0.8,
    extraHeaders: {'anthropic-beta': 'x'},
    options: {
      'enableServerWebSearch': true,
      'thinkingBudget': 2000,
      'nested': {
        'list': [1, 'a'],
      },
    },
  );
  final minimal = ProviderProfile(
    id: 'p2',
    name: 'Ollama',
    type: ProviderType.openaiCompatible,
    defaultModel: 'llama',
    privacy: PrivacyLevel.local,
    authMethod: const NoAuth(),
  );

  group('ProviderProfile JSON', () {
    test('round trip full', () {
      final decoded = ProviderProfile.fromJson(viaString(full.toJson()));
      expect(decoded, full);
      expect(decoded.hashCode, full.hashCode);
    });
    test('round trip minimal omits nulls', () {
      final json = minimal.toJson();
      expect(json.keys, isNot(contains('baseUrl')));
      expect(json.keys, isNot(contains('budgetMonthly')));
      expect(json.keys, isNot(contains('warnThreshold')));
      expect(json.keys, isNot(contains('extraHeaders')));
      expect(json.keys, isNot(contains('options')));
      expect(ProviderProfile.fromJson(viaString(json)).options, isEmpty);
      expect(ProviderProfile.fromJson(viaString(json)), minimal);
    });
    test('integer warnThreshold is accepted', () {
      final json = viaString(minimal.toJson())..['warnThreshold'] = 1;
      expect(ProviderProfile.fromJson(json).warnThreshold, 1.0);
    });
    test('contains secret reference, never a value', () {
      final text = jsonEncode(full.toJson());
      expect(text, contains('provider.p1.key'));
    });
    test('rejects unknown type and privacy', () {
      final badType = viaString(full.toJson())..['type'] = 'gemini';
      final badPrivacy = viaString(full.toJson())..['privacy'] = 'secret';
      final badHeaders = viaString(full.toJson())..['extraHeaders'] = {'a': 1};
      final badOptions = viaString(full.toJson())..['options'] = [1];
      expect(() => ProviderProfile.fromJson(badOptions), throwsFormatException);
      expect(() => ProviderProfile.fromJson(badType), throwsFormatException);
      expect(() => ProviderProfile.fromJson(badPrivacy), throwsFormatException);
      expect(() => ProviderProfile.fromJson(badHeaders), throwsFormatException);
    });
  });

  group('ProviderProfile', () {
    test('copyWith replaces each field', () {
      final c = minimal.copyWith(
        id: 'x',
        name: 'n',
        type: ProviderType.fake,
        baseUrl: 'http://h',
        defaultModel: 'm',
        privacy: PrivacyLevel.tee,
        authMethod: const ApiKeyAuth('r'),
        budgetMonthly: 1,
        warnThreshold: 0.5,
        extraHeaders: {'a': 'b'},
        options: {'o': 1},
      );
      expect(c.options, {'o': 1});
      expect(c.id, 'x');
      expect(c.name, 'n');
      expect(c.type, ProviderType.fake);
      expect(c.baseUrl, 'http://h');
      expect(c.defaultModel, 'm');
      expect(c.privacy, PrivacyLevel.tee);
      expect(c.authMethod, const ApiKeyAuth('r'));
      expect(c.budgetMonthly, 1);
      expect(c.warnThreshold, 0.5);
      expect(c.extraHeaders, {'a': 'b'});
      expect(full.copyWith(), full);
    });

    test('equality distinguishes fields', () {
      expect(full, isNot(full.copyWith(id: 'other')));
      expect(full, isNot(full.copyWith(name: 'other')));
      expect(full, isNot(full.copyWith(type: ProviderType.fake)));
      expect(full, isNot(full.copyWith(baseUrl: 'other')));
      expect(full, isNot(full.copyWith(defaultModel: 'other')));
      expect(full, isNot(full.copyWith(privacy: PrivacyLevel.eu)));
      expect(full, isNot(full.copyWith(authMethod: const NoAuth())));
      expect(full, isNot(full.copyWith(budgetMonthly: 1)));
      expect(full, isNot(full.copyWith(warnThreshold: 0.1)));
      expect(full, isNot(full.copyWith(extraHeaders: {})));
      expect(full, isNot(full.copyWith(options: {'thinkingBudget': 1})));
      expect(
        full.copyWith(
          options: {
            'a': [1],
          },
        ),
        full.copyWith(
          options: {
            'a': [1],
          },
        ),
      );
      expect(
        full
            .copyWith(
              options: {
                'a': [1],
              },
            )
            .hashCode,
        full
            .copyWith(
              options: {
                'a': [1],
              },
            )
            .hashCode,
      );
      expect(full.toString(), contains('p1'));
    });

    test('extraHeaders are unmodifiable', () {
      expect(() => full.extraHeaders['x'] = 'y', throwsUnsupportedError);
      expect(() => full.options['x'] = 'y', throwsUnsupportedError);
    });
  });
}
