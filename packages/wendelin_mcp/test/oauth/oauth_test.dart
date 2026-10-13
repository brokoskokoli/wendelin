import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

final redirect = Uri.parse('app.wendelin://oauth/mcp');

void main() {
  late FakeMcpServer server;
  late http.Client httpClient;
  late FakeMcpSecrets secrets;
  late FixedClock clock;

  setUp(() async {
    server = await FakeMcpServer.start(
      auth: FakeAuthMode.oauth,
      tools: [FakeMcpTool('whoami')],
    );
    httpClient = http.Client();
    secrets = FakeMcpSecrets();
    clock = FixedClock(DateTime.utc(2026, 10, 13, 9));
  });

  tearDown(() async {
    httpClient.close();
    await server.close();
  });

  McpServerConfig config({
    String? clientId,
    Uri? url,
    List<String> scopes = const [],
  }) => McpServerConfig(
    id: 'oauth-srv',
    name: 'OAuth-Server',
    slug: 'oauth',
    url: url ?? server.url,
    auth: McpOAuth(
      tokenRef: 'mcp.oauth.tokens',
      clientRef: 'mcp.oauth.client',
      clientId: clientId,
      scopes: scopes,
    ),
  );

  McpOAuthFlow flow({AuthorizationBrowser? browser}) => McpOAuthFlow(
    client: httpClient,
    secrets: secrets,
    browser: browser ?? FakeAuthorizationBrowser(),
    redirectUri: redirect,
    clock: clock,
    random: Random(7),
  );

  McpClient mcp(McpServerConfig c, McpOAuthFlow f) => McpClient(
    config: c,
    httpClient: httpClient,
    secrets: secrets,
    oauth: f,
    clock: clock,
  );

  group('vollständiger Ablauf', () {
    test('401 → Discovery → DCR → PKCE → Token → Aufruf', () async {
      final c = config();
      final f = flow();
      final client = mcp(c, f);
      await expectLater(
        client.ping(),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.authRequired,
          ),
        ),
      );
      final challenge = client.lastChallenge;
      expect(challenge, contains('resource_metadata='));

      final tokens = await f.authorize(c, challenge: challenge);

      // Discovery (RFC 9728 → RFC 8414).
      final paths = server.requests.map((r) => r.uri.path).toList();
      expect(paths, contains('/.well-known/oauth-protected-resource/mcp'));
      expect(paths, contains('/.well-known/oauth-authorization-server/as'));
      // DCR (RFC 7591): öffentlicher Client mit Redirect.
      final registration = server.registrations.values.single;
      expect(registration['redirect_uris'], [redirect.toString()]);
      expect(registration['token_endpoint_auth_method'], 'none');
      // Autorisierung: PKCE S256, state, resource, scope.
      final auth = server.lastAuthorization!;
      expect(auth['code_challenge_method'], 'S256');
      expect(auth['resource'], server.url.toString());
      expect(auth['scope'], 'mcp:tools');
      expect(auth['client_id'], server.registrations.keys.single);
      expect(auth['state']!.length, 32);
      // Token-Tausch: Verifier passt zur Challenge, resource mitgeschickt.
      final exchange = server.tokenRequests.single;
      final verifier = exchange['code_verifier']!;
      expect(verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(verifier), isTrue);
      expect(s256Challenge(verifier), auth['code_challenge']);
      expect(exchange['resource'], server.url.toString());
      expect(exchange['redirect_uri'], redirect.toString());
      expect(tokens.expiresAt, clock.now().add(const Duration(hours: 1)));

      // Tokens nur in den Secrets.
      expect(secrets.writes, ['mcp.oauth.client', 'mcp.oauth.tokens']);
      expect(secrets.values['mcp.oauth.tokens'], contains(tokens.accessToken));
      expect(jsonEncode(c.toJson()), isNot(contains(tokens.accessToken)));

      await client.ping();
      final last = server.requests.lastWhere((r) => r.rpcMethod == 'ping');
      expect(last.headers['authorization'], 'Bearer ${tokens.accessToken}');
      expect(await f.hasUsableTokens(c), isTrue);
      await client.dispose();
    });

    test('ohne Challenge: Well-known-Pfad der Ressource', () async {
      final c = config();
      await flow().authorize(c);
      expect(
        server.requests.first.uri.path,
        '/.well-known/oauth-protected-resource/mcp',
      );
      expect(server.accessTokens, hasLength(1));
    });

    test(
      'ohne Ressourcen-Metadaten: Server ist sein eigener Autorisierungsserver',
      () async {
        server.withResourceMetadata = false;
        final c = config(scopes: ['eigene']);
        await flow().authorize(c);
        expect(
          server.requests.map((r) => r.uri.path),
          contains('/.well-known/oauth-authorization-server'),
        );
        expect(server.lastAuthorization!['scope'], 'eigene');
        expect(server.lastAuthorization!['resource'], server.url.toString());
      },
    );

    test('OIDC-Fallback für die Metadaten', () async {
      server.oidcOnly = true;
      await flow().authorize(config());
      expect(
        server.requests.map((r) => r.uri.path),
        contains('/.well-known/openid-configuration/as'),
      );
    });

    test('konfigurierte Client-Id: keine Registrierung', () async {
      server.dynamicRegistration = false;
      await flow().authorize(config(clientId: 'wendelin-app'));
      expect(server.registrations, isEmpty);
      expect(server.lastAuthorization!['client_id'], 'wendelin-app');
      expect(secrets.writes, ['mcp.oauth.tokens']);
    });

    test('gespeicherte Registrierung wird wiederverwendet', () async {
      final f = flow();
      await f.authorize(config());
      await f.authorize(config());
      expect(server.registrations, hasLength(1));
    });

    test('kaputte gespeicherte Registrierung → neu registrieren', () async {
      secrets.values['mcp.oauth.client'] = '{kaputt';
      await flow().authorize(config());
      expect(server.registrations, hasLength(1));
    });
  });

  group('Abweisungen', () {
    Future<void> expectKind(Future<Object?> f, McpErrorKind kind) =>
        expectLater(
          f,
          throwsA(isA<McpException>().having((e) => e.kind, 'kind', kind)),
        );

    test('ohne DCR und ohne Client-Id', () async {
      server.dynamicRegistration = false;
      await expectKind(flow().authorize(config()), McpErrorKind.authRequired);
    });

    test('Mix-up: Metadaten mit fremdem issuer werden abgelehnt', () async {
      server.metadataIssuer = 'https://evil.example/as';
      await expectKind(flow().authorize(config()), McpErrorKind.rejected);
      expect(server.lastAuthorization, isNull);
    });

    test('issuer mit abschließendem Schrägstrich gilt als gleich', () async {
      server.metadataIssuer = '${server.issuer}/';
      await flow().authorize(config());
      expect(server.accessTokens, hasLength(1));
    });

    test('Server ohne PKCE S256', () async {
      server.announceS256 = false;
      await expectKind(flow().authorize(config()), McpErrorKind.protocol);
    });

    test('state stimmt nicht', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {...back.queryParameters, 'state': 'gefälscht'},
        ),
      );
      await expectKind(
        flow(browser: browser).authorize(config()),
        McpErrorKind.rejected,
      );
      expect(server.tokenRequests, isEmpty);
      expect(secrets.values.containsKey('mcp.oauth.tokens'), isFalse);
    });

    test('Fehler vom Autorisierungsserver', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {
            'error': 'access_denied',
            'state': back.queryParameters['state'],
          },
        ),
      );
      await expectLater(
        flow(browser: browser).authorize(config()),
        throwsA(
          isA<McpException>()
              .having((e) => e.kind, 'kind', McpErrorKind.authRequired)
              .having(
                (e) => e.message,
                'message',
                'Anmeldung abgelehnt: access_denied',
              ),
        ),
      );
    });

    test('Fehler ohne passenden state: verworfen, kein fremder Text', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {'error': 'Bitte https://evil.example besuchen'},
        ),
      );
      await expectLater(
        flow(browser: browser).authorize(config()),
        throwsA(
          isA<McpException>()
              .having((e) => e.kind, 'kind', McpErrorKind.rejected)
              .having((e) => e.message, 'message', isNot(contains('evil'))),
        ),
      );
    });

    test('Fehlertext außerhalb von RFC 6749 wird nicht übernommen', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {
            'error': 'Ruf 0800 an',
            'state': back.queryParameters['state'],
          },
        ),
      );
      await expectLater(
        flow(browser: browser).authorize(config()),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            'Anmeldung abgelehnt: unbekannter Fehler',
          ),
        ),
      );
    });

    test('Browser bricht ab: Text ohne Typnamen', () async {
      await expectLater(
        flow(browser: FakeAuthorizationBrowser(fail: true)).authorize(config()),
        throwsA(
          isA<McpException>().having(
            (e) => e.message,
            'message',
            'Anmeldung abgebrochen',
          ),
        ),
      );
    });

    test('Rückleitung an fremde Adresse', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => Uri.parse('https://evil.example/cb?${back.query}'),
      );
      await expectKind(
        flow(browser: browser).authorize(config()),
        McpErrorKind.rejected,
      );
    });

    test('falscher Aussteller (iss)', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {
            ...back.queryParameters,
            'iss': 'https://evil.example',
          },
        ),
      );
      await expectKind(
        flow(browser: browser).authorize(config()),
        McpErrorKind.rejected,
      );
    });

    test('kein Code', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {
            for (final e in back.queryParameters.entries)
              if (e.key != 'code') e.key: e.value,
          },
        ),
      );
      await expectKind(
        flow(browser: browser).authorize(config()),
        McpErrorKind.protocol,
      );
    });

    test('falscher Verifier wird vom Server abgelehnt', () async {
      final browser = FakeAuthorizationBrowser(
        tamper: (back) => back.replace(
          queryParameters: {...back.queryParameters, 'code': 'code-unbekannt'},
        ),
      );
      await expectKind(
        flow(browser: browser).authorize(config()),
        McpErrorKind.server,
      );
    });

    test('Nutzer bricht ab', () async {
      await expectKind(
        flow(browser: FakeAuthorizationBrowser(fail: true)).authorize(config()),
        McpErrorKind.authRequired,
      );
    });

    test('Ressourcen-Metadaten für anderen Server', () async {
      final other = server.origin.replace(path: '/anders');
      await expectKind(
        flow().authorize(
          config(url: other),
          challenge:
              'Bearer resource_metadata="${server.origin}/.well-known/oauth-protected-resource/mcp"',
        ),
        McpErrorKind.rejected,
      );
    });

    test('Ressourcen-Metadaten fehlen trotz Challenge', () async {
      await expectKind(
        flow().authorize(
          config(),
          challenge: 'Bearer resource_metadata="/.well-known/fehlt"',
        ),
        McpErrorKind.protocol,
      );
    });

    test('Autorisierungsserver ohne Metadaten', () async {
      final empty = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      empty.listen((req) async {
        req.response.statusCode = 404;
        await req.response.close();
      });
      addTearDown(() => empty.close(force: true));
      await expectKind(
        flow().authorize(
          config(url: Uri.parse('http://127.0.0.1:${empty.port}/mcp')),
        ),
        McpErrorKind.protocol,
      );
    });

    test('kein OAuth-Server konfiguriert', () {
      expect(
        () => flow().authorize(
          McpServerConfig(id: 'x', name: 'x', slug: 'x', url: server.url),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Erneuern und Ablauf', () {
    test('abgelaufenes Token wird vor dem Aufruf erneuert', () async {
      final c = config();
      final f = flow();
      final first = await f.authorize(c);
      clock.advance(const Duration(hours: 2));
      expect(first.isExpired(clock.now()), isTrue);
      final client = mcp(c, f);
      await client.ping();
      final refresh = server.tokenRequests.last;
      expect(refresh['grant_type'], 'refresh_token');
      expect(refresh['refresh_token'], first.refreshToken);
      expect(refresh['resource'], server.url.toString());
      final stored = (await f.storedTokens(c))!;
      expect(stored.accessToken, isNot(first.accessToken));
      expect(stored.expiresAt, clock.now().add(const Duration(hours: 1)));
      await client.dispose();
    });

    test(
      'Server lehnt gültiges Token ab (401) → einmal erneuern, wiederholen',
      () async {
        final c = config();
        final f = flow();
        await f.authorize(c);
        final client = mcp(c, f);
        await client.ping();
        server.expireAccessTokens();
        await client.callTool('whoami', const {});
        expect(server.tokenRequests.last['grant_type'], 'refresh_token');
        await client.dispose();
      },
    );

    test('Erneuern abgelehnt → Anmeldung abgelaufen', () async {
      final c = config();
      final f = flow();
      await f.authorize(c);
      server
        ..rejectRefresh = true
        ..expireAccessTokens();
      final client = mcp(c, f);
      await expectLater(
        client.ping(),
        throwsA(
          isA<McpException>()
              .having((e) => e.kind, 'kind', McpErrorKind.authRequired)
              .having((e) => e.message, 'message', contains('abgelaufen')),
        ),
      );
      await client.dispose();
    });

    test('ohne Refresh-Token: abgelaufen heißt neu anmelden', () async {
      server.issueRefreshTokens = false;
      final c = config();
      final f = flow();
      await f.authorize(c);
      expect(await f.hasUsableTokens(c), isTrue);
      clock.advance(const Duration(hours: 2));
      expect(await f.hasUsableTokens(c), isFalse);
      await expectLater(
        f.accessToken(c),
        throwsA(
          isA<McpException>().having(
            (e) => e.kind,
            'kind',
            McpErrorKind.authRequired,
          ),
        ),
      );
    });

    test(
      'parallele Aufrufe teilen sich eine Erneuerung (Token-Rotation)',
      () async {
        final c = config();
        final f = flow();
        final first = await f.authorize(c);
        clock.advance(const Duration(hours: 2));
        final tokens = await Future.wait([
          f.accessToken(c),
          f.accessToken(c),
          f.accessToken(c, forceRefresh: true),
        ]);
        expect(tokens.toSet(), hasLength(1));
        expect(tokens.first, isNot(first.accessToken));
        expect(
          server.tokenRequests.where((r) => r['grant_type'] == 'refresh_token'),
          hasLength(1),
        );
        // Danach ist eine neue Erneuerung wieder möglich.
        await f.refresh(c);
        expect(
          server.tokenRequests.where((r) => r['grant_type'] == 'refresh_token'),
          hasLength(2),
        );
      },
    );

    test('nach gescheitertem Refresh ist ein neuer Refresh möglich', () async {
      final c = config();
      final f = flow();
      await f.authorize(c);
      server.rejectRefresh = true;
      await expectLater(
        Future.wait([f.refresh(c), f.refresh(c)]),
        throwsA(isA<McpException>()),
      );
      expect(
        server.tokenRequests.where((r) => r['grant_type'] == 'refresh_token'),
        hasLength(1),
      );
      server.rejectRefresh = false;
      final renewed = await f.refresh(c);
      expect(server.accessTokens, contains(renewed.accessToken));
      expect(
        server.tokenRequests.where((r) => r['grant_type'] == 'refresh_token'),
        hasLength(2),
      );
    });

    test('parallele Client-Aufrufe nach Ablauf: ein Refresh', () async {
      final c = config();
      final f = flow();
      await f.authorize(c);
      final client = mcp(c, f);
      await client.ping();
      clock.advance(const Duration(hours: 2));
      await Future.wait([client.ping(), client.ping(), client.ping()]);
      expect(
        server.tokenRequests.where((r) => r['grant_type'] == 'refresh_token'),
        hasLength(1),
      );
      await client.dispose();
    });

    test(
      'kaputte gespeicherte Client-Daten beim Erneuern → McpException',
      () async {
        final c = config();
        final f = flow();
        await f.authorize(c);
        for (final broken in [
          '{kaputt',
          jsonEncode({
            'client_id': server.registrations.keys.single,
            'client_secret': 42,
          }),
        ]) {
          secrets.values['mcp.oauth.client'] = broken;
          await expectLater(
            f.refresh(c),
            throwsA(
              isA<McpException>()
                  .having((e) => e.kind, 'kind', McpErrorKind.authRequired)
                  .having((e) => e.message, 'message', contains('beschädigt')),
            ),
          );
        }
      },
    );

    test(
      'gespeicherte Registrierung mit falschem Secret-Typ → kein Absturz',
      () async {
        final f = flow();
        await f.authorize(config());
        final stored = jsonDecode(
          secrets.values['mcp.oauth.client']!,
        ) as Map<String, Object?>;
        secrets.values['mcp.oauth.client'] = jsonEncode({
          ...stored,
          'client_secret': 42,
        });
        await f.authorize(config());
        expect(server.registrations, hasLength(1));
      },
    );

    test('nicht angemeldet, Abmelden, kaputte Token-Daten', () async {
      final c = config();
      final f = flow();
      expect(await f.hasUsableTokens(c), isFalse);
      await expectLater(f.accessToken(c), throwsA(isA<McpException>()));
      await expectLater(f.refresh(c), throwsA(isA<McpException>()));
      await f.authorize(c);
      await f.signOut(c);
      expect(await f.storedTokens(c), isNull);
      secrets.values['mcp.oauth.tokens'] = 'kein json';
      expect(await f.storedTokens(c), isNull);
      secrets.values['mcp.oauth.tokens'] = '[1]';
      expect(await f.storedTokens(c), isNull);
    });
  });

  group('Bausteine', () {
    test('PKCE S256 nach RFC 7636 Anhang B', () {
      expect(
        s256Challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
      final token = randomToken(Random(1));
      expect(token.length, 64);
      expect(randomToken(Random(1), 43).length, 43);
    });

    for (final (header, expected) in [
      (null, <String, String>{}),
      ('Bearer', <String, String>{}),
      (
        'Bearer resource_metadata="https://a.example/.well-known/x", scope="a b"',
        {
          'resource_metadata': 'https://a.example/.well-known/x',
          'scope': 'a b',
        },
      ),
      (
        'Bearer error="invalid_token", error_description="Der \\"Token\\" ist alt"',
        {'error': 'invalid_token', 'error_description': 'Der "Token" ist alt'},
      ),
      ('Bearer realm=fake, Scope=x', {'realm': 'fake', 'scope': 'x'}),
    ]) {
      test('WWW-Authenticate: $header', () {
        expect(parseChallenge(header), expected);
      });
    }

    test('Ablaufpuffer 30 s', () {
      final expires = DateTime.utc(2026, 10, 13, 12);
      final t = McpTokenSet(
        accessToken: 'a',
        expiresAt: expires,
        tokenEndpoint: Uri.parse('https://as.example/token'),
        clientId: 'c',
        resource: 'r',
      );
      for (final (offset, expired) in [
        (-31, false),
        (-30, true),
        (-29, true),
        (0, true),
        (10, true),
      ]) {
        expect(
          t.isExpired(expires.add(Duration(seconds: offset))),
          expired,
          reason: 'Abstand $offset s',
        );
      }
      final forever = McpTokenSet(
        accessToken: 'a',
        tokenEndpoint: Uri.parse('https://as.example/token'),
        clientId: 'c',
        resource: 'r',
      );
      expect(forever.isExpired(DateTime.utc(2100)), isFalse);
    });

    test('kanonische Ressource', () {
      expect(
        canonicalResource(Uri.parse('HTTPS://MCP.Example.com/Mcp#frag')),
        'https://mcp.example.com/Mcp',
      );
    });

    test('Token-Satz: JSON-Rundreise, toString ohne Secrets', () {
      final t = McpTokenSet(
        accessToken: 'geheimes-access-token',
        refreshToken: 'geheimes-refresh-token',
        expiresAt: DateTime.utc(2026),
        scope: 'a',
        tokenEndpoint: Uri.parse('https://as.example/token'),
        clientId: 'c',
        resource: 'https://mcp.example/mcp',
      );
      final back = McpTokenSet.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(t.toString(), isNot(contains('geheim')));
      expect(() => McpTokenSet.fromJson(const {}), throwsFormatException);
    });
  });
}
