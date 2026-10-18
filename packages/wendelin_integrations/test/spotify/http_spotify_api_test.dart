import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'spotify_server.dart';

Matcher _port(PortErrorKind kind, [Object? message]) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', message ?? anything),
);

final _auth = SpotifyAuth(
  accessToken: 'tok-access',
  refreshToken: 'tok-refresh',
  expiresAt: DateTime.utc(2030),
);

void main() {
  group('Anfragen und Antworten', () {
    test('Suche: Adresse, Token, Treffer; null-Einträge und fremde URIs '
        'fallen weg', () async {
      final server = SpotifyServer((_) => jsonResponse(searchAllJson));
      final hits = await server.api().search(
        _auth,
        'queen',
        SpotifyKind.values.toSet(),
        limit: 3,
      );
      final req = server.requests.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/v1/search');
      expect(req.url.queryParameters, {
        'q': 'queen',
        'type': 'track,album,artist,playlist',
        'limit': '3',
      });
      expect(req.headers['Authorization'], 'Bearer tok-access');
      expect(hits.map((h) => h.label), [
        'Bohemian Rhapsody – Queen',
        'Somebody to Love – Queen, George Michael',
        'A Night at the Opera – Queen',
        'Queen',
        'This Is Queen – Spotify',
      ]);
      expect(hits.first.kind, SpotifyKind.track);
      expect(hits.first.uri, 'spotify:track:4u7EnebtmKWzUH433cf5Qv');
    });

    test(
      'Wiedergabezustand: Titel, Position, Gerät; 204 = nichts aktiv',
      () async {
        var answer = jsonResponse(playbackJson);
        final server = SpotifyServer((_) => answer);
        final p = (await server.api().playback(_auth))!;
        expect(server.requests.single.url.path, '/v1/me/player');
        expect(p.isPlaying, isTrue);
        expect(p.title, 'Bohemian Rhapsody');
        expect(p.by, 'Queen');
        expect(p.album, 'A Night at the Opera');
        expect(p.trackUri, 'spotify:track:4u7EnebtmKWzUH433cf5Qv');
        expect(p.contextUri, 'spotify:album:6X9k3iKZrQK3SDKpOZnB7M');
        expect(p.progressMs, 61000);
        expect(p.deviceName, 'Pixel 8');
        answer = http.Response('', 204);
        expect(await server.api().playback(_auth), isNull);
      },
    );

    test('Podcast-Folge: Sendung als Künstler, keine Titel-URI', () async {
      final server = SpotifyServer(
        (_) => jsonResponse({
          'is_playing': false,
          'item': {
            'type': 'episode',
            'name': 'Folge 7',
            'uri': 'spotify:episode:abcdefghij1234',
            'show': {'name': 'Der Podcast'},
          },
        }),
      );
      final p = (await server.api().playback(_auth))!;
      expect(p.by, 'Der Podcast');
      expect(p.trackUri, isNull);
      expect(p.isPlaying, isFalse);
    });

    test('Geräte: ohne Id übersprungen, eingeschränkt markiert', () async {
      final server = SpotifyServer((_) => jsonResponse(devicesJson));
      final d = await server.api().devices(_auth);
      expect(d.map((e) => e.id), ['dev1', 'dev2']);
      expect(d.last.isRestricted, isTrue);
    });

    test('Play: Titel, Kontext, Fortsetzen, Gerät', () async {
      final server = SpotifyServer((_) => http.Response('', 204));
      final api = server.api();
      await api.play(_auth, uris: ['spotify:track:abcdefghij1234']);
      await api.play(
        _auth,
        contextUri: 'spotify:album:abcdefghij1234',
        deviceId: 'dev1',
      );
      await api.play(_auth);
      await api.play(
        _auth,
        uris: ['spotify:track:abcdefghij1234'],
        positionMs: 5,
      );
      await api.play(
        _auth,
        contextUri: 'spotify:playlist:abcdefghij1234',
        offsetUri: 'spotify:track:abcdefghij1234',
        positionMs: 7,
      );
      final r = server.requests;
      expect(r.every((e) => e.method == 'PUT'), isTrue);
      expect(r[0].url.path, '/v1/me/player/play');
      expect(r[0].json, {
        'uris': ['spotify:track:abcdefghij1234'],
      });
      expect(r[1].url.queryParameters, {'device_id': 'dev1'});
      expect(r[1].json, {'context_uri': 'spotify:album:abcdefghij1234'});
      expect(r[2].body, isEmpty);
      expect((r[3].json! as Map)['position_ms'], 5);
      expect(r[4].json, {
        'context_uri': 'spotify:playlist:abcdefghij1234',
        'offset': {'uri': 'spotify:track:abcdefghij1234'},
        'position_ms': 7,
      });
    });

    test('Pause, weiter, zurück, Warteschlange', () async {
      final server = SpotifyServer((_) => http.Response('', 204));
      final api = server.api();
      await api.pause(_auth);
      await api.next(_auth, deviceId: 'd');
      await api.previous(_auth);
      await api.queueAdd(_auth, 'spotify:track:abcdefghij1234');
      final r = server.requests;
      expect([r[0].method, r[0].url.path], ['PUT', '/v1/me/player/pause']);
      expect([r[1].method, r[1].url.path], ['POST', '/v1/me/player/next']);
      expect(r[1].url.queryParameters, {'device_id': 'd'});
      expect([r[2].method, r[2].url.path], ['POST', '/v1/me/player/previous']);
      expect([r[3].method, r[3].url.path], ['POST', '/v1/me/player/queue']);
      expect(r[3].url.queryParameters['uri'], 'spotify:track:abcdefghij1234');
    });
  });

  group('Token', () {
    test('Code tauschen: PKCE-Formular ohne Client-Secret', () async {
      final now = DateTime.utc(2026, 10, 18, 12);
      final server = SpotifyServer((_) => jsonResponse(tokenJson));
      final auth = await server
          .api(clock: FixedClock(now))
          .exchangeCode(
            clientId: 'cid',
            code: 'abc',
            verifier: 'ver',
            redirect: spotifyRedirect,
          );
      final req = server.requests.single;
      expect(req.url.toString(), 'https://accounts.spotify.com/api/token');
      expect(req.form, {
        'grant_type': 'authorization_code',
        'code': 'abc',
        'redirect_uri': 'app.wendelin://oauth/spotify',
        'client_id': 'cid',
        'code_verifier': 'ver',
      });
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(auth.accessToken, 'BQDnew-access');
      expect(auth.refreshToken, 'AQDnew-refresh');
      expect(auth.expiresAt, now.add(const Duration(hours: 1)));
    });

    test('Erneuern: ein neuer Refresh-Token ersetzt den alten', () async {
      final server = SpotifyServer((_) => jsonResponse(tokenJson));
      final auth = await server.api().refresh('cid', _auth);
      expect(auth.refreshToken, 'AQDnew-refresh');
      expect(auth.refreshToken, isNot(_auth.refreshToken));
    });

    test(
      'Erneuern: behält den alten Refresh-Token, wenn keiner kommt',
      () async {
        final server = SpotifyServer(
          (_) => jsonResponse({...tokenJson}..remove('refresh_token')),
        );
        final auth = await server.api().refresh('cid', _auth);
        expect(server.requests.single.form, {
          'grant_type': 'refresh_token',
          'refresh_token': 'tok-refresh',
          'client_id': 'cid',
        });
        expect(auth.refreshToken, 'tok-refresh');
      },
    );

    test(
      'invalid_grant (400) = abgelehnt, ohne Antworttext in der Meldung',
      () async {
        final server = SpotifyServer(
          (_) => jsonResponse({
            'error': 'invalid_grant',
            'error_description': 'Refresh token revoked GEHEIM',
          }, 400),
        );
        await expectLater(
          server.api().refresh('cid', _auth),
          throwsA(
            isA<PortException>()
                .having((e) => e.kind, 'kind', PortErrorKind.permissionDenied)
                .having((e) => e.message, 'message', isNot(contains('GEHEIM'))),
          ),
        );
      },
    );

    test('Antwort ohne Felder = unerwartetes Format', () async {
      final server = SpotifyServer((_) => jsonResponse({'access_token': 'x'}));
      await expectLater(
        server.api().refresh('cid', _auth),
        _port(PortErrorKind.failed, contains('Format')),
      );
    });
  });

  group('Fehler', () {
    SpotifyApi apiAnswering(http.Response r, {void Function(String)? log}) =>
        SpotifyServer((_) => r).api(log: log);

    test('401: Token abgelehnt', () {
      expect(
        apiAnswering(
          jsonResponse(errorJson(401, 'The access token expired'), 401),
        ).playback(_auth),
        _port(PortErrorKind.permissionDenied, contains('401')),
      );
    });

    test('403 PREMIUM_REQUIRED: Premium-Text', () {
      expect(
        apiAnswering(
          jsonResponse(
            errorJson(
              403,
              'Player command failed: Premium required',
              'PREMIUM_REQUIRED',
            ),
            403,
          ),
        ).pause(_auth),
        throwsA(same(spotifyPremiumRequired)),
      );
      expect(spotifyPremiumRequired.message, contains('Premium'));
    });

    test('403 sonst: Verweigert, Hinweis auf User Management', () {
      expect(
        apiAnswering(
          jsonResponse(
            errorJson(403, 'User not registered in the Developer Dashboard'),
            403,
          ),
        ).search(_auth, 'x', {SpotifyKind.track}),
        _port(PortErrorKind.rejected, contains('User Management')),
      );
    });

    test('404 NO_ACTIVE_DEVICE: kein Gerät; andere 404 nicht', () async {
      await expectLater(
        apiAnswering(
          jsonResponse(
            errorJson(
              404,
              'Player command failed: No active device found',
              'NO_ACTIVE_DEVICE',
            ),
            404,
          ),
        ).play(_auth),
        throwsA(same(spotifyNoDevice)),
      );
      expect(spotifyNoDevice.message, contains('Spotify-App'));
      await expectLater(
        apiAnswering(http.Response('Not found', 404)).next(_auth),
        throwsA(
          isA<PortException>().having(
            (e) => e,
            'e',
            isNot(same(spotifyNoDevice)),
          ),
        ),
      );
    });

    test('429: Sperre bis Retry-After, danach wieder frei', () async {
      final clock = FixedClock(DateTime.utc(2026, 10, 18));
      final lines = <String>[];
      var limited = true;
      final server = SpotifyServer(
        (_) => limited
            ? http.Response('', 429, headers: {'retry-after': '20'})
            : jsonResponse(devicesJson),
      );
      final api = server.api(clock: clock, log: lines.add);
      await expectLater(
        api.devices(_auth),
        _port(PortErrorKind.unavailable, contains('Anfragelimit')),
      );
      limited = false;
      await expectLater(api.devices(_auth), throwsA(isA<PortException>()));
      expect(server.requests, hasLength(1));
      clock.advance(const Duration(seconds: 21));
      expect(await api.devices(_auth), isNotEmpty);
    });

    test('5xx, unerreichbar, Zeitüberschreitung: unavailable', () async {
      await expectLater(
        apiAnswering(http.Response('', 503)).devices(_auth),
        _port(PortErrorKind.unavailable, contains('503')),
      );
      final dead = HttpSpotifyApi(
        client: MockClient((_) async => throw http.ClientException('x')),
      );
      await expectLater(
        dead.devices(_auth),
        _port(PortErrorKind.unavailable, contains('nicht erreichbar')),
      );
      final slow = HttpSpotifyApi(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        slow.devices(_auth),
        _port(PortErrorKind.unavailable, contains('Zeitüberschreitung')),
      );
    });

    test('HTML statt JSON = unerwartetes Format', () {
      expect(
        apiAnswering(http.Response('<html>', 200)).devices(_auth),
        _port(PortErrorKind.failed, contains('Format')),
      );
    });

    test('Log enthält weder Token noch Suchtext noch Antworttext', () async {
      final lines = <String>[];
      final api = apiAnswering(jsonResponse(searchTrackJson), log: lines.add);
      await api.search(_auth, 'geheime suche', {SpotifyKind.track});
      final text = lines.join('\n');
      expect(text, contains('search'));
      for (final secret in ['tok-access', 'geheime', 'Bohemian']) {
        expect(text, isNot(contains(secret)));
      }
    });
  });
}
