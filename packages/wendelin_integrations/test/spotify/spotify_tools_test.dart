import 'dart:convert';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import '../helpers.dart';

const _clientId = '0123456789abcdef0123456789abcdef';
const _phone = SpotifyDevice(id: 'dev1', name: 'Pixel 8');
const _bohemian = 'spotify:track:4u7EnebtmKWzUH433cf5Qv';
const _album = 'spotify:album:6X9k3iKZrQK3SDKpOZnB7M';

void main() {
  late FakeSpotifyApi api;
  late FakeSpotifySecrets secrets;
  late FakeSpotifyLauncher launcher;
  late SpotifyIntegration spotify;
  late List<String> errors;

  setUp(() async {
    api = FakeSpotifyApi(devices: [_phone]);
    secrets = FakeSpotifySecrets(storedClientId: _clientId);
    secrets.storedAuth = await api.exchangeCode(
      clientId: _clientId,
      code: FakeSpotifyApi.validCode,
      verifier: 'v' * 64,
      redirect: spotifyRedirect,
    );
    launcher = FakeSpotifyLauncher();
    errors = [];
    api.methodCalls.clear();
    spotify = SpotifyIntegration(
      api,
      secrets,
      launcher: launcher,
      onError: (m, _) => errors.add(m),
      delay: (_) async {},
    );
  });

  Tool tool(String name) => spotify.tools.singleWhere((t) => t.name == name);
  Future<ToolOutcome> call(
    String name, [
    Map<String, Object?> args = const {},
  ]) => tool(name).execute(args, ctx());
  Map<String, Object?> data(ToolOutcome o) =>
      jsonDecode(o.text.substring(o.text.indexOf('{'))) as Map<String, Object?>;

  void playing({String uri = _bohemian, String title = 'Bohemian Rhapsody'}) {
    api
      ..activeDeviceId = 'dev1'
      ..playing = true
      ..trackUri = uri
      ..title = title
      ..positionMs = 61000;
  }

  test('Risiko je Tool: Suche und Läuft-gerade lesen, Rest schreibt', () {
    expect(
      {for (final t in spotify.tools) t.name: t.risk},
      {
        'spotify__search': RiskLevel.read,
        'spotify__now_playing': RiskLevel.read,
        'spotify__play': RiskLevel.write,
        'spotify__pause': RiskLevel.write,
        'spotify__next': RiskLevel.write,
        'spotify__previous': RiskLevel.write,
        'spotify__queue_add': RiskLevel.write,
      },
    );
  });

  group('Suche', () {
    test('Titel: Treffer mit URI, als Daten gekennzeichnet', () async {
      final o = await call('spotify__search', {
        'query': 'bohemian',
        'type': 'track',
      });
      expect(o.isError, isFalse);
      expect(o.text, startsWith(spotifyDataNotice));
      expect(data(o)['results'], [
        {
          'kind': 'track',
          'name': 'Bohemian Rhapsody',
          'by': 'Queen',
          'uri': _bohemian,
        },
      ]);
    });

    test('ohne Art: alle vier Arten', () async {
      final o = await call('spotify__search', {'query': 'queen'});
      final kinds = [
        for (final r in data(o)['results']! as List<Object?>)
          (r! as Map)['kind'],
      ];
      expect(kinds.toSet(), {'track', 'album', 'artist', 'playlist'});
    });

    test('leer, zu lang, Zeilenumbruch, unbekannte Art', () async {
      for (final args in [
        <String, Object?>{},
        {'query': ''},
        {'query': 'a' * (maxSpotifyQuery + 1)},
        {'query': 'a\nb'},
        {'query': 'x', 'type': 'podcast'},
      ]) {
        final o = await call('spotify__search', args);
        expect(o.isError, isTrue, reason: '$args');
        expect(o.text, startsWith('Ungültige Argumente'));
      }
      expect(api.methodCalls, isEmpty);
    });
  });

  group('Wiedergabe starten', () {
    test(
      'Titel per Suche: spielt den ersten Treffer, Antwort nennt ihn',
      () async {
        final o = await call('spotify__play', {'query': 'bohemian rhapsody'});
        expect(o.isError, isFalse);
        expect(o.text, contains('Bohemian Rhapsody – Queen'));
        expect(api.lastPlay!.uris, [_bohemian]);
        expect(api.lastPlay!.contextUri, isNull);
        expect(api.playing, isTrue);
      },
    );

    test('Album, Künstler, Playlist laufen als Kontext', () async {
      await call('spotify__play', {'query': 'night opera', 'type': 'album'});
      expect(api.lastPlay!.contextUri, _album);
      expect(api.lastPlay!.uris, isNull);
      await call('spotify__play', {'query': 'queen', 'type': 'artist'});
      expect(api.lastPlay!.contextUri, startsWith('spotify:artist:'));
      await call('spotify__play', {
        'query': 'this is queen',
        'type': 'playlist',
      });
      expect(api.lastPlay!.contextUri, startsWith('spotify:playlist:'));
    });

    test('URI aus der Suche wird direkt gespielt (ohne Suche)', () async {
      await call('spotify__play', {'uri': _album});
      expect(api.methodCalls, isNot(contains('search')));
      expect(api.lastPlay!.contextUri, _album);
    });

    test('fremde oder kaputte URI wird abgelehnt', () async {
      for (final uri in [
        'https://evil.example/x',
        'spotify:user:foo',
        'spotify:track:../../x',
        'spotify:track:kurz',
      ]) {
        final o = await call('spotify__play', {'uri': uri});
        expect(o.isError, isTrue, reason: uri);
      }
      expect(api.lastPlay, isNull);
    });

    test('ohne Treffer: Fehlertext, nichts gestartet', () async {
      final o = await call('spotify__play', {'query': 'gibtesnicht'});
      expect(o.isError, isTrue);
      expect(o.text, contains('findet zu „gibtesnicht“ nichts'));
      expect(api.lastPlay, isNull);
    });

    test('ohne Angaben: setzt die pausierte Wiedergabe fort', () async {
      playing();
      api.playing = false;
      final o = await call('spotify__play');
      expect(o.text, 'Wiedergabe fortgesetzt.');
      expect(api.lastPlay!.uris, isNull);
      expect(api.lastPlay!.contextUri, isNull);
      expect(api.playing, isTrue);
    });

    test('kein Gerät: Spotify-App wird geweckt, dann spielt es', () async {
      api
        ..knownDevices.clear()
        ..activeDeviceId = null;
      launcher.onWake = () => api.knownDevices.add(_phone);
      final o = await call('spotify__play', {'query': 'bohemian'});
      expect(o.isError, isFalse);
      expect(launcher.wakes, 1);
      expect(api.lastPlay!.deviceId, 'dev1');
    });

    test('kein Gerät und App startet nicht: Fehlertext', () async {
      api
        ..knownDevices.clear()
        ..activeDeviceId = null;
      launcher.installed = false;
      final o = await call('spotify__play', {'query': 'bohemian'});
      expect(o.isError, isTrue);
      expect(o.text, contains('Kein aktives Spotify-Gerät'));
    });

    test(
      'kein Premium: Fehlertext, App bleibt aktiv (kein Fehlerzustand)',
      () async {
        api.premium = false;
        final o = await call('spotify__play', {'query': 'bohemian'});
        expect(o.isError, isTrue);
        expect(o.text, contains('Premium'));
        expect(errors, isEmpty);
      },
    );

    test('nicht angemeldet: Fehlertext mit Weg zur Einrichtung', () async {
      secrets.storedAuth = null;
      spotify = SpotifyIntegration(api, secrets);
      final o = await call('spotify__play', {'query': 'bohemian'});
      expect(o.isError, isTrue);
      expect(o.text, contains('nicht angemeldet'));
    });

    test('Undo, wenn vorher nichts lief: pausiert', () async {
      final o = await call('spotify__play', {'query': 'bohemian'});
      expect(o.undo!.label, 'Pausieren');
      await o.undo!.run();
      expect(api.playing, isFalse);
    });

    test(
      'Undo, wenn vorher etwas lief: das vorherige Stück an der Stelle',
      () async {
        playing(uri: 'spotify:track:7hQJA50XrCWABAu5v6QZ4i', title: 'Davor');
        final o = await call('spotify__play', {'uri': _album});
        expect(o.undo!.label, 'Vorheriges wieder spielen');
        await o.undo!.run();
        expect(api.lastPlay!.uris, ['spotify:track:7hQJA50XrCWABAu5v6QZ4i']);
        expect(api.lastPlay!.positionMs, 61000);
      },
    );

    for (final context in [
      'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M',
      'spotify:album:6X9k3iKZrQK3SDKpOZnB7M',
    ]) {
      test(
        'Undo, wenn vorher $context lief: Kontext, Titel und Stelle',
        () async {
          playing(uri: 'spotify:track:7hQJA50XrCWABAu5v6QZ4i', title: 'Davor');
          api.contextUri = context;
          final o = await call('spotify__play', {'uri': _album});
          await o.undo!.run();
          expect(api.lastPlay!.contextUri, context);
          expect(
            api.lastPlay!.offsetUri,
            'spotify:track:7hQJA50XrCWABAu5v6QZ4i',
          );
          expect(api.lastPlay!.uris, isNull);
          expect(api.lastPlay!.positionMs, 61000);
        },
      );
    }

    test(
      'Undo bei Künstler-Kontext (kein Offset möglich): nur der Titel',
      () async {
        playing(uri: 'spotify:track:7hQJA50XrCWABAu5v6QZ4i', title: 'Davor');
        api.contextUri = 'spotify:artist:1dfeR4HaWDbWqFHLkxsg1d';
        final o = await call('spotify__play', {'uri': _album});
        await o.undo!.run();
        expect(api.lastPlay!.uris, ['spotify:track:7hQJA50XrCWABAu5v6QZ4i']);
        expect(api.lastPlay!.contextUri, isNull);
      },
    );

    test('Undo von „weiter“ pausiert wieder', () async {
      playing();
      api.playing = false;
      final o = await call('spotify__play');
      await o.undo!.run();
      expect(api.playing, isFalse);
    });
  });

  group('Pause, Weiter, Zurück', () {
    test('Pause: pausiert; Undo setzt fort', () async {
      playing();
      final o = await call('spotify__pause');
      expect(o.isError, isFalse);
      expect(o.text, contains('Pausiert: Bohemian Rhapsody'));
      expect(api.playing, isFalse);
      expect(o.undo!.label, 'Weiter abspielen');
      await o.undo!.run();
      expect(api.playing, isTrue);
    });

    test(
      'Pause, wenn nichts läuft: Hinweis ohne Fehler und ohne Undo',
      () async {
        final o = await call('spotify__pause');
        expect(o.isError, isFalse);
        expect(o.text, contains('nichts'));
        expect(o.undo, isNull);
        expect(api.methodCalls, ['playback']);
      },
    );

    test('Pause, wenn schon pausiert: nichts zu tun', () async {
      playing();
      api.playing = false;
      final o = await call('spotify__pause');
      expect(o.undo, isNull);
      expect(api.methodCalls, isNot(contains('pause')));
    });

    test('Weiter und Zurück: Befehl geht ans Gerät, kein Undo', () async {
      playing();
      expect((await call('spotify__next')).undo, isNull);
      expect((await call('spotify__previous')).isError, isFalse);
      expect(api.methodCalls, containsAllInOrder(['next', 'previous']));
    });

    test('Weiter ohne Gerät: Fehlertext, App wird nicht geweckt', () async {
      api.knownDevices.clear();
      final o = await call('spotify__next');
      expect(o.isError, isTrue);
      expect(o.text, contains('Kein aktives Spotify-Gerät'));
      expect(launcher.wakes, 0);
    });
  });

  group('Läuft gerade', () {
    test('Titel, Künstler-Feld, Gerät', () async {
      playing();
      final o = await call('spotify__now_playing');
      expect(o.text, startsWith(spotifyDataNotice));
      expect(data(o), {
        'playing': true,
        'title': 'Bohemian Rhapsody',
        'device': 'Pixel 8',
      });
    });

    test('nichts aktiv: klare Antwort, kein Fehler', () async {
      final o = await call('spotify__now_playing');
      expect(o.isError, isFalse);
      expect(o.text, 'Spotify spielt gerade nichts.');
    });
  });

  group('Warteschlange', () {
    test('Titel per Suche kommt in die Warteschlange', () async {
      playing();
      final o = await call('spotify__queue_add', {'query': 'somebody love'});
      expect(o.isError, isFalse);
      expect(api.queue, ['spotify:track:7hQJA50XrCWABAu5v6QZ4i']);
      expect(o.undo, isNull);
    });

    test('Album-URI wird abgelehnt', () async {
      final o = await call('spotify__queue_add', {'uri': _album});
      expect(o.isError, isTrue);
      expect(o.text, contains('nur Titel'));
      expect(api.queue, isEmpty);
    });

    test('ohne Gerät wird die App geweckt', () async {
      api
        ..knownDevices.clear()
        ..activeDeviceId = null;
      launcher.onWake = () => api.knownDevices.add(_phone);
      final o = await call('spotify__queue_add', {'uri': _bohemian});
      expect(o.isError, isFalse);
      expect(launcher.wakes, 1);
    });
  });

  group('Bestätigungstexte', () {
    test('nennen, was passiert, und werfen bei Unsinn nie', () {
      expect(
        tool('spotify__play').describeForConfirmation({'query': 'Queen'}),
        'Auf Spotify „Queen“ abspielen',
      );
      expect(
        tool('spotify__play').describeForConfirmation({}),
        'Spotify-Wiedergabe fortsetzen',
      );
      expect(
        tool('spotify__pause').describeForConfirmation({}),
        'Spotify pausieren',
      );
      expect(
        tool('spotify__play').describeForConfirmation({'query': 5}),
        'Auf Spotify abspielen',
      );
    });
  });

  group('Integration', () {
    test(
      'Einrichtung: ohne Token fehlt der Login, mit Token vollständig',
      () async {
        expect((await spotify.setupState()).complete, isTrue);
        secrets.storedAuth = null;
        expect((await spotify.setupState()).missingSteps, [
          SpotifyIntegration.loginStep,
        ]);
        expect(spotify.id, 'spotify');
        expect(spotify.platforms, {AppPlatform.android});
        expect((await spotify.checkAvailability()).available, isTrue);
      },
    );

    test('Verbindung prüfen: null bei Erfolg, Text bei Fehler', () async {
      expect(await spotify.reconnect(), isNull);
      api.failNext(
        'playback',
        const PortException(
          PortErrorKind.unavailable,
          'Spotify nicht erreichbar',
        ),
      );
      final f = await spotify.reconnect();
      expect(f!.service, 'spotify');
      expect(f.kind, PortErrorKind.unavailable);
      expect(f.message, 'Spotify nicht erreichbar');
    });

    test('abgelaufene Anmeldung pausiert die Integration', () async {
      api
        ..expireTokens()
        ..revokeRefresh();
      final o = await call('spotify__now_playing');
      expect(o.isError, isTrue);
      expect(errors, ['Spotify-Anmeldung abgelaufen']);
    });
  });

  group('feste Bestätigung', () {
    test(
      'play mit Suche: neutraler Satz, Trefferbezeichnung ist Servername',
      () async {
        expectFixed(
          await call('spotify__play', {'query': 'bohemian rhapsody'}),
          tool('spotify__play'),
          'media.play',
          de: 'Die Wiedergabe läuft.',
        );
      },
    );

    test('play mit uri: spotify.playing mit der genannten Adresse', () async {
      expectFixed(
        await call('spotify__play', {
          'uri': 'spotify:track:4uLU6hMCjMI75M1A2tKUQC',
        }),
        tool('spotify__play'),
        'spotify.playing',
        de: 'Es spielt jetzt spotify:track:4uLU6hMCjMI75M1A2tKUQC.',
      );
    });

    test('play ohne Angaben: media.play', () async {
      playing();
      api.playing = false;
      expectFixed(
        await call('spotify__play'),
        tool('spotify__play'),
        'media.play',
        de: 'Die Wiedergabe läuft.',
      );
    });

    test('play ohne Treffer → Fehler ohne Satz', () async {
      final o = await call('spotify__play', {'query': 'gibtesnicht'});
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });

    test('pause, next, previous', () async {
      playing();
      expectFixed(
        await call('spotify__pause'),
        tool('spotify__pause'),
        'media.pause',
      );
      expectFixed(
        await call('spotify__next'),
        tool('spotify__next'),
        'media.next',
      );
      expectFixed(
        await call('spotify__previous'),
        tool('spotify__previous'),
        'media.previous',
      );
    });

    test('pause, wenn nichts läuft → kein Satz', () async {
      final o = await call('spotify__pause');
      expect(o.isError, isFalse);
      expect(o.fixed, isNull);
    });

    test('next ohne Gerät → Fehler ohne Satz', () async {
      api.knownDevices.clear();
      final o = await call('spotify__next');
      expect(o.isError, isTrue);
      expect(o.fixed, isNull);
    });
  });
}
