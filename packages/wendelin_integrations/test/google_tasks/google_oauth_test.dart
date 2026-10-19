import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _client = GoogleClient(
  id: 'id-1.apps.googleusercontent.com',
  secret: 'GOCSPX-canary-secret',
);
const _canaries = [
  'GOCSPX-canary-secret',
  'refresh-canary',
  'access-canary',
  'code-canary',
];

void main() {
  late List<http.Request> requests;
  final now = DateTime.utc(2026, 10, 13, 12);

  HttpGoogleOAuthApi api(http.Response Function(http.Request r) h) {
    requests = [];
    return HttpGoogleOAuthApi(
      client: MockClient((r) async {
        requests.add(r);
        return h(r);
      }),
      clock: () => now,
    );
  }

  http.Response json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Matcher refused(String contains_) => throwsA(
    isA<PortException>()
        .having((e) => e.kind, 'kind', PortErrorKind.permissionDenied)
        .having(
          (e) => e.message,
          'm',
          allOf(
            contains(contains_),
            predicate<String>((m) => _canaries.every((c) => !m.contains(c))),
          ),
        ),
  );

  test(
    'Code-Tausch: Formular mit Verifier, Secret, Redirect; Ablauf berechnet',
    () async {
      final a = api(
        (r) => json({
          'access_token': 'access-canary',
          'expires_in': 3599,
          'refresh_token': 'refresh-canary',
          'scope': googleTasksScope,
          'token_type': 'Bearer',
        }),
      );
      final set = await a.exchangeCode(
        client: _client,
        code: 'code-canary',
        verifier: 'ver',
        redirect: Uri.parse('http://127.0.0.1:5000/oauth2/callback'),
      );
      expect(set.refreshToken, 'refresh-canary');
      expect(set.access.expiresAt, now.add(const Duration(seconds: 3599)));
      expect(
        requests.single.url.toString(),
        'https://oauth2.googleapis.com/token',
      );
      expect(requests.single.bodyFields, {
        'grant_type': 'authorization_code',
        'client_id': _client.id,
        'client_secret': _client.secret,
        'code': 'code-canary',
        'code_verifier': 'ver',
        'redirect_uri': 'http://127.0.0.1:5000/oauth2/callback',
      });
      expect(set.toString(), isNot(contains('canary')));
    },
  );

  test(
    'Code-Tausch ohne Refresh-Token oder ohne Tasks-Scope wird abgelehnt',
    () async {
      for (final body in [
        {'access_token': 'a', 'expires_in': 10, 'scope': googleTasksScope},
        {
          'access_token': 'a',
          'expires_in': 10,
          'refresh_token': 'r',
          'scope': 'openid',
        },
      ]) {
        final a = api((r) => json(body));
        await expectLater(
          a.exchangeCode(
            client: _client,
            code: 'c',
            verifier: 'v',
            redirect: Uri.parse('http://127.0.0.1:1/x'),
          ),
          throwsA(
            isA<PortException>().having(
              (e) => e.kind,
              'k',
              PortErrorKind.rejected,
            ),
          ),
        );
      }
    },
  );

  test('Refresh: neues Access-Token, kein neues Refresh-Token', () async {
    final a = api(
      (r) => json({'access_token': 'access-canary', 'expires_in': 3600}),
    );
    final set = await a.refresh(_client, 'refresh-canary');
    expect(set.refreshToken, isNull);
    expect(requests.single.bodyFields['grant_type'], 'refresh_token');
    expect(requests.single.bodyFields['refresh_token'], 'refresh-canary');
  });

  test(
    'Abgelehnt: invalid_grant, invalid_client, fremder Code; Body bleibt weg',
    () async {
      await expectLater(
        api(
          (r) => json({
            'error': 'invalid_grant',
            'error_description': 'refresh-canary',
          }, 400),
        ).refresh(_client, 'refresh-canary'),
        refused('invalid_grant'),
      );
      await expectLater(
        api((r) => json({'error': 'invalid_client'}, 401))
            .refresh(_client, 'x'),
        refused('Client-ID oder Client-Secret'),
      );
      await expectLater(
        api((r) => json({'error': 'Böse <script>'}, 400)).refresh(_client, 'x'),
        refused('unbekannt'),
      );
    },
  );

  test('Netz, Serverfehler, 429, kaputte Antwort', () async {
    final down = HttpGoogleOAuthApi(
      client: MockClient((r) async => throw const SocketException('weg')),
    );
    await expectLater(
      down.refresh(_client, 'x'),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'k',
          PortErrorKind.unavailable,
        ),
      ),
    );
    for (final s in [500, 429]) {
      await expectLater(
        api((r) => http.Response('', s)).refresh(_client, 'x'),
        throwsA(
          isA<PortException>().having(
            (e) => e.kind,
            'k',
            PortErrorKind.unavailable,
          ),
        ),
      );
    }
    for (final b in ['<html>', '{}', '{"access_token":"a"}']) {
      await expectLater(
        api((r) => http.Response(b, 200)).refresh(_client, 'x'),
        throwsA(
          isA<PortException>().having((e) => e.kind, 'k', PortErrorKind.failed),
        ),
      );
    }
  });

  test('Revoke: POST mit Token, Fehler werden verschluckt', () async {
    await api((r) => http.Response('', 200)).revoke('refresh-canary');
    expect(
      requests.single.url.toString(),
      'https://oauth2.googleapis.com/revoke',
    );
    expect(requests.single.bodyFields, {'token': 'refresh-canary'});
    await HttpGoogleOAuthApi(
      client: MockClient((r) async => throw const SocketException('weg')),
    ).revoke('x');
  });
}
