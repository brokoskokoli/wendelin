import 'dart:async';

import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _clientId = '0123456789abcdef0123456789abcdef';

Matcher _port(PortErrorKind kind, [Object? message]) => throwsA(
  isA<PortException>()
      .having((e) => e.kind, 'kind', kind)
      .having((e) => e.message, 'message', message ?? anything),
);

void main() {
  late FixedClock clock;
  late FakeSpotifyApi api;
  late FakeSpotifySecrets secrets;
  late FakeSpotifyLauncher launcher;
  late List<String> errors;
  late List<PortErrorKind> kinds;
  late int recovered;
  late List<Duration> waits;
  late SpotifySession session;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 10, 18, 12));
    api = FakeSpotifyApi()..now = clock.now;
    secrets = FakeSpotifySecrets(storedClientId: _clientId);
    secrets.storedAuth = await api.exchangeCode(
      clientId: _clientId,
      code: FakeSpotifyApi.validCode,
      verifier: 'v' * 64,
      redirect: spotifyRedirect,
    );
    api.methodCalls.clear();
    launcher = FakeSpotifyLauncher();
    errors = [];
    kinds = [];
    recovered = 0;
    waits = [];
    session = SpotifySession(
      api,
      secrets,
      launcher: launcher,
      clock: clock,
      onError: (m, k) {
        errors.add(m);
        kinds.add(k);
      },
      onRecovered: () => recovered++,
      delay: (d) async {
        waits.add(d);
        clock.advance(d);
      },
    );
  });

  group('Token', () {
    test('gültiger Token wird ohne Erneuerung benutzt', () async {
      await session.run(api.playback);
      expect(api.methodCalls, ['playback']);
    });

    test('abgelaufener Token (Uhr) wird vor dem Aufruf erneuert und '
        'gespeichert', () async {
      clock.advance(const Duration(minutes: 59, seconds: 30));
      await session.run(api.playback);
      expect(api.methodCalls, ['refresh', 'playback']);
      expect((await secrets.auth())!.accessToken, api.currentAccess);
    });

    test('401 erneuert einmal und wiederholt den Aufruf einmal', () async {
      api.expireTokens();
      await session.run(api.playback);
      expect(api.methodCalls, ['playback', 'refresh', 'playback']);
      expect(errors, isEmpty);
    });

    test('parallele Aufrufe teilen eine Erneuerung', () async {
      api.expireTokens();
      await Future.wait([session.run(api.playback), session.run(api.devices)]);
      expect(api.methodCalls.where((m) => m == 'refresh'), hasLength(1));
    });

    test('Anmeldung widerrufen: Token gelöscht, Fehlerzustand, Hinweis auf '
        'Neuanmeldung', () async {
      api
        ..expireTokens()
        ..revokeRefresh();
      await expectLater(
        session.run(api.playback),
        _port(PortErrorKind.permissionDenied, contains('neu anmelden')),
      );
      expect(errors, ['Spotify-Anmeldung abgelaufen']);
      expect(kinds, [PortErrorKind.permissionDenied]);
      expect(session.failed, isTrue);
      expect(await secrets.auth(), isNull);
      // Danach: nicht angemeldet, ohne weiteren Fehlerzustand.
      await expectLater(
        session.run(api.playback),
        throwsA(same(spotifyNotLoggedIn)),
      );
      expect(errors, hasLength(1));
    });

    test('Refresh-Token-Rotation: der neue Wert wird gespeichert und beim '
        'nächsten Erneuern benutzt', () async {
      api.rotateRefresh = true;
      api.expireTokens();
      await session.run(api.playback);
      final first = (await secrets.auth())!.refreshToken;
      expect(first, isNot('refresh-1'));
      api.expireTokens();
      await session.run(api.playback);
      expect((await secrets.auth())!.refreshToken, isNot(first));
      expect(errors, isEmpty);
    });

    test('401 trotz erfolgreicher Erneuerung (z. B. fehlender Scope) löscht '
        'die Anmeldung nicht', () async {
      Future<void> deny(SpotifyAuth a) async =>
          throw const PortException(PortErrorKind.permissionDenied, 'HTTP 401');
      await expectLater(
        session.run(deny),
        _port(PortErrorKind.permissionDenied, contains('verweigert')),
      );
      expect(await secrets.auth(), isNotNull);
      expect(api.methodCalls, ['refresh']);
      // Die Anmeldung gilt weiter.
      await session.run(api.playback);
    });

    test('Erneuerung nach Löschen der Anmeldung: nicht angemeldet, kein '
        'Refresh mit veraltetem Token', () async {
      final gate = Completer<void>();
      final slow = session.run((a) async {
        await gate.future;
        throw const PortException(PortErrorKind.permissionDenied, 'HTTP 401');
      });
      final slowResult = expectLater(slow, throwsA(same(spotifyNotLoggedIn)));
      await Future<void>.delayed(Duration.zero);
      api
        ..expireTokens()
        ..revokeRefresh();
      await expectLater(session.run(api.playback), throwsA(anything));
      expect(await secrets.auth(), isNull);
      api.methodCalls.clear();
      gate.complete();
      await slowResult;
      expect(api.methodCalls, isEmpty);
    });

    test(
      'Fehler ohne Anmeldedaten: nicht angemeldet, kein Fehlerzustand',
      () async {
        secrets.storedAuth = null;
        session = SpotifySession(
          api,
          secrets,
          onError: (m, _) => errors.add(m),
        );
        await expectLater(
          session.run(api.playback),
          throwsA(same(spotifyNotLoggedIn)),
        );
        expect(errors, isEmpty);
      },
    );

    test(
      'Netzfehler beim Refresh: Tokens bleiben, nächster Lauf gelingt',
      () async {
        api
          ..expireTokens()
          ..failNext(
            'refresh',
            const PortException(PortErrorKind.unavailable, 'offline'),
          );
        await expectLater(
          session.run(api.playback),
          _port(PortErrorKind.unavailable),
        );
        expect(await secrets.auth(), isNotNull);
        expect(errors, isEmpty);
        expect(session.failed, isFalse);
        await session.run(api.playback);
      },
    );

    test('Offline/5xx/Limit pausieren die Integration nicht', () async {
      api.failNext(
        'playback',
        const PortException(
          PortErrorKind.unavailable,
          'Spotify nicht erreichbar',
        ),
      );
      await expectLater(
        session.run(api.playback),
        _port(PortErrorKind.unavailable),
      );
      expect(errors, isEmpty);
      expect(session.failed, isFalse);
    });

    test(
      'neue Anmeldung nach dem Fehler: erster Erfolg ruft onRecovered',
      () async {
        api
          ..expireTokens()
          ..failNext(
            'refresh',
            const PortException(PortErrorKind.permissionDenied, 'abgelehnt'),
          );
        await expectLater(session.run(api.playback), throwsA(anything));
        expect(recovered, 0);
        secrets.storedAuth = await api.exchangeCode(
          clientId: _clientId,
          code: FakeSpotifyApi.validCode,
          verifier: 'v' * 64,
          redirect: spotifyRedirect,
        );
        await session.forget();
        await session.run(api.playback);
        await session.run(api.playback);
        expect(recovered, 1);
        expect(session.failed, isFalse);
      },
    );
  });

  group('Geräte', () {
    const phone = SpotifyDevice(
      id: 'dev1',
      name: 'Pixel 8',
      type: 'Smartphone',
    );

    test('aktives Gerät: Befehl läuft ohne Umweg', () async {
      api
        ..knownDevices.add(phone)
        ..activeDeviceId = 'dev1';
      await session.playbackCommand(
        (a, d) => api.play(a, deviceId: d),
        wake: true,
      );
      expect(api.lastPlay!.deviceId, isNull);
      expect(launcher.wakes, 0);
    });

    test(
      'kein aktives Gerät, aber bekanntes: wird gewählt, App bleibt zu',
      () async {
        api.knownDevices.add(phone);
        await session.playbackCommand(
          (a, d) => api.play(a, deviceId: d),
          wake: true,
        );
        expect(api.lastPlay!.deviceId, 'dev1');
        expect(launcher.wakes, 0);
      },
    );

    test('eingeschränkte Geräte werden nicht gewählt', () async {
      api.knownDevices.add(
        const SpotifyDevice(id: 'echo', name: 'Echo', isRestricted: true),
      );
      launcher.installed = false;
      await expectLater(
        session.playbackCommand((a, d) => api.play(a, deviceId: d), wake: true),
        throwsA(same(spotifyNoDevice)),
      );
    });

    test('kein Gerät: App wecken, auf das Gerät warten, dann Befehl', () async {
      // The app shows its device only after the third wait.
      session = SpotifySession(
        api,
        secrets,
        launcher: launcher,
        clock: clock,
        delay: (d) async {
          waits.add(d);
          clock.advance(d);
          if (waits.length == 3) api.knownDevices.add(phone);
        },
      );
      await session.playbackCommand(
        (a, d) => api.play(a, deviceId: d),
        wake: true,
      );
      expect(launcher.wakes, 1);
      expect(waits, hasLength(3));
      expect(api.lastPlay!.deviceId, 'dev1');
    });

    test(
      'App startet nie ein Gerät: nach den Versuchen „kein Gerät“',
      () async {
        await expectLater(
          session.playbackCommand(
            (a, d) => api.play(a, deviceId: d),
            wake: true,
          ),
          throwsA(same(spotifyNoDevice)),
        );
        expect(launcher.wakes, 1);
        expect(waits, hasLength(SpotifySession.wakeAttempts));
        expect(spotifyNoDevice.message, contains('Spotify-App'));
      },
    );

    test(
      'Spotify nicht installiert: gleich „kein Gerät“, ohne Warten',
      () async {
        launcher.installed = false;
        await expectLater(
          session.playbackCommand(
            (a, d) => api.play(a, deviceId: d),
            wake: true,
          ),
          throwsA(same(spotifyNoDevice)),
        );
        expect(waits, isEmpty);
      },
    );

    test('Befehle ohne wake (Pause, Weiter) wecken die App nicht', () async {
      await expectLater(
        session.playbackCommand((a, d) => api.next(a, deviceId: d)),
        throwsA(same(spotifyNoDevice)),
      );
      expect(launcher.wakes, 0);
      expect(api.methodCalls, ['next']);
    });

    test('ohne Launcher (andere Plattform): „kein Gerät“', () async {
      session = SpotifySession(api, secrets, clock: clock);
      await expectLater(
        session.playbackCommand((a, d) => api.play(a, deviceId: d), wake: true),
        throwsA(same(spotifyNoDevice)),
      );
    });

    test('Kein Premium: eigener Text, kein Fehlerzustand', () async {
      api
        ..premium = false
        ..knownDevices.add(phone)
        ..activeDeviceId = 'dev1';
      await expectLater(
        session.playbackCommand((a, d) => api.pause(a, deviceId: d)),
        throwsA(same(spotifyPremiumRequired)),
      );
      expect(errors, isEmpty);
    });
  });

  group('Wiedergabe starten (startPlayback)', () {
    const phone = SpotifyDevice(
      id: 'dev1',
      name: 'Pixel 8',
      type: 'Smartphone',
    );
    const desktop = SpotifyDevice(id: 'pc', name: 'Büro-PC', type: 'Computer');
    const speaker = SpotifyDevice(
      id: 'spk',
      name: 'Wohnzimmer',
      type: 'Speaker',
    );
    late List<(String, Map<String, Object>)> diag;
    late FakeSpotifyHostDevice host;

    int count(String method) =>
        api.methodCalls.where((m) => m == method).length;

    setUp(() {
      diag = [];
      host = FakeSpotifyHostDevice();
      session = SpotifySession(
        api,
        secrets,
        launcher: launcher,
        hostDevice: host,
        clock: clock,
        onDiagnostic: (e, f) => diag.add((e, f)),
        delay: (d) async {
          waits.add(d);
          clock.advance(d);
        },
      );
    });

    Future<SpotifyStart> start({String? name}) => session.startPlayback(
      (a, d) => api.play(
        a,
        deviceId: d,
        uris: ['spotify:track:4u7EnebtmKWzUH433cf5Qv'],
      ),
      deviceName: name,
    );

    test('fremdes Gerät „aktiv“: der Befehl geht trotzdem ans Handy', () async {
      api
        ..knownDevices.addAll([desktop, phone])
        ..activeDeviceId = 'pc';
      final r = await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(r.confirmed, isTrue);
      expect(r.isPhone, isTrue);
      expect(launcher.wakes, 0);
    });

    test('fremdes Gerät nimmt Befehle an, spielt aber nichts: Handy gewählt', () async {
      // Spotify answers 204 for the dead desktop device; only the phone plays.
      api
        ..knownDevices.addAll([desktop, phone])
        ..activeDeviceId = 'pc'
        ..frozenDeviceIds.add('pc');
      final r = await start();
      expect(r.confirmed, isTrue);
      expect(api.activeDeviceId, 'dev1');
      expect(launcher.wakes, 0);
    });

    test(
      'device.id null im Wiedergabezustand: Prüfung über den Gerätenamen',
      () async {
        api
          ..knownDevices.add(phone)
          ..playbackWithoutDeviceId = true;
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(launcher.wakes, 0);
      },
    );

    test('device.id null und anderer Gerätename: nicht bestätigt (kein '
        'Namens-Raten)', () async {
      api
        ..knownDevices.addAll([desktop, phone])
        ..playbackWithoutDeviceId = true;
      // The phone is the target, but the desktop is the one that plays.
      api.onPlay = () => api.activeDeviceId = 'pc';
      await expectLater(start(), throwsA(isA<PortException>()));
    });

    test(
      'Handy gelistet, aber eingefroren: einmal wecken, dann spielt es',
      () async {
        api
          ..knownDevices.add(phone)
          ..frozenDeviceIds.add('dev1');
        launcher.onWake = api.frozenDeviceIds.clear;
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(launcher.wakes, 1);
        expect(count('play'), 2);
        expect(
          diag.map((e) => e.$1),
          containsAllInOrder(['spotify-device', 'spotify-verify']),
        );
      },
    );

    test(
      'kein Gerät: App wecken, auf das Handy warten, dann spielen',
      () async {
        launcher.onWake = () => api.knownDevices.add(phone);
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(launcher.wakes, 1);
        expect(api.lastPlay!.deviceId, 'dev1');
      },
    );

    test('Wecken hilft nicht: ehrlicher Fehler, genau ein Wecken', () async {
      api
        ..knownDevices.add(phone)
        ..frozenDeviceIds.add('dev1');
      await expectLater(
        start(),
        throwsA(
          isA<PortException>().having(
            (e) => e.message,
            'message',
            contains('auf dem Handy läuft nichts'),
          ),
        ),
      );
      expect(launcher.wakes, 1);
      expect(count('play'), 2);
      expect(count('playback'), 2 * SpotifySession.verifyAttempts);
    });

    test(
      'Wecken erzeugt nur ein totes Handy: trotzdem nur ein Wecken',
      () async {
        launcher.onWake = () {
          api.knownDevices.add(phone);
          api.frozenDeviceIds.add('dev1');
        };
        await expectLater(start(), throwsA(isA<PortException>()));
        expect(launcher.wakes, 1);
        expect(count('play'), 1);
      },
    );

    test('spielt auf einem anderen Gerät: nicht bestätigt', () async {
      api.knownDevices.addAll([desktop, phone]);
      api.onPlay = () => api
        ..activeDeviceId = 'pc'
        ..playing = true;
      await expectLater(start(), throwsA(isA<PortException>()));
      expect(diag.last.$2['result'], 'other-device');
    });

    test('kein Gerät und App nicht installiert: „kein Gerät“', () async {
      launcher.installed = false;
      await expectLater(start(), throwsA(same(spotifyNoDevice)));
      expect(count('play'), 0);
    });

    test(
      '429 beim Prüfen: sofort Schluss, nicht geprüft, kein Wecken',
      () async {
        api.knownDevices.add(phone);
        api.onPlay = () => api.failNext(
          'playback',
          const PortException(PortErrorKind.unavailable, 'Anfragelimit'),
        );
        final r = await start();
        expect(r.confirmed, isFalse);
        expect(count('playback'), 1);
        expect(count('play'), 1);
        expect(launcher.wakes, 0);
        expect(diag.last.$2['result'], 'unchecked');
      },
    );

    test('benanntes Gerät (ohne Groß/Klein, Teilname)', () async {
      api.knownDevices.addAll([phone, speaker]);
      final r = await start(name: 'wohnzimmer');
      expect(api.lastPlay!.deviceId, 'spk');
      expect(r.isPhone, isFalse);
      expect(r.confirmed, isTrue);
      expect(launcher.wakes, 0);
    });

    test('unbekanntes Gerät: Fehler mit Liste, nichts gesendet', () async {
      api.knownDevices.addAll([phone, speaker]);
      await expectLater(
        start(name: 'Keller'),
        throwsA(
          isA<PortException>()
              .having((e) => e.kind, 'kind', PortErrorKind.notFound)
              .having(
                (e) => e.message,
                'message',
                contains('Pixel 8, Wohnzimmer'),
              ),
        ),
      );
      expect(count('play'), 0);
      expect(launcher.wakes, 0);
    });

    test('Handy per Namen erkannt, wenn mehrere Smartphones da sind', () async {
      const other = SpotifyDevice(id: 'x', name: 'Tablet', type: 'Smartphone');
      api.knownDevices.addAll([other, phone]);
      host.hostNames = {' PIXEL 8 '};
      await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(diag.first.$2['via'], 'name');
      // Remembered: found again without the name.
      host.hostNames = {};
      await start();
      expect(diag[2].$2['via'], 'cache');
    });

    test('zwei Smartphones, kein Name: kein Handy, App wird geweckt', () async {
      const other = SpotifyDevice(id: 'x', name: 'Tablet', type: 'Smartphone');
      api.knownDevices.addAll([other, phone]);
      launcher.installed = false;
      await expectLater(start(), throwsA(same(spotifyNoDevice)));
    });

    group('Bestätigung', () {
      late FakeMediaControlPort media;

      MediaSnapshot snap({String? package, bool playing = true}) =>
          MediaSnapshot(
            packageName: package ?? spotifyAndroidPackage,
            appName: 'Spotify',
            playing: playing,
          );

      void withMedia() {
        session = SpotifySession(
          api,
          secrets,
          launcher: launcher,
          hostDevice: host,
          media: media,
          clock: clock,
          onDiagnostic: (e, f) => diag.add((e, f)),
          delay: (d) async {
            waits.add(d);
            clock.advance(d);
          },
        );
      }

      setUp(() => media = FakeMediaControlPort());

      test('Web-API: is_playing mit stehendem Fortschritt gilt nicht '
          '(totes Gerät), einmal wecken', () async {
        api
          ..knownDevices.add(phone)
          ..stuckDeviceIds.add('dev1');
        await expectLater(start(), throwsA(isA<PortException>()));
        expect(diag.last.$2['result'], 'stalled');
        expect(diag.last.$2['via'], 'api');
        expect(launcher.wakes, 1);
        expect(count('play'), 2);
      });

      test('Web-API: wachsender Fortschritt bestätigt (via=api)', () async {
        api.knownDevices.add(phone);
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(diag.last.$2['via'], 'api');
        expect(count('playback'), 2);
      });

      test('Handy mit Sitzungszugriff: Spotify-Sitzung spielt bestätigt, '
          'auch wenn die Web-API stehen bleibt (via=session)', () async {
        api
          ..knownDevices.add(phone)
          ..stuckDeviceIds.add('dev1');
        media.snapshot = snap();
        withMedia();
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(diag.last.$2['via'], 'session');
        expect(count('playback'), 0);
      });

      test('Fehler von hasSessionAccess: zurück auf die Web-API, kein '
          'Abbruch', () async {
        api.knownDevices.add(phone);
        media
          ..snapshot = snap(package: 'com.google.android.youtube')
          ..failNext('hasSessionAccess');
        withMedia();
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(diag.last.$2['via'], 'api');
        expect(media.methodCalls, isNot(contains('nowPlaying')));
      });

      test('andere App spielt: Web-API entscheidet, kein Wecken', () async {
        api.knownDevices.add(phone);
        media.snapshot = snap(package: 'com.google.android.youtube');
        withMedia();
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(diag.last.$2['via'], 'api');
        expect(launcher.wakes, 0);
        expect(count('play'), 1);
      });

      test('andere App spielt, Web-API bestätigt nicht: nicht geprüft, '
          'kein Wecken, kein Neustart', () async {
        api
          ..knownDevices.add(phone)
          ..stuckDeviceIds.add('dev1');
        media.snapshot = snap(package: 'com.google.android.youtube');
        withMedia();
        final r = await start();
        expect(r.confirmed, isFalse);
        expect(launcher.wakes, 0);
        expect(count('play'), 1);
        expect(diag.last.$2['result'], isNot('playing'));
      });

      test('Spotify-Sitzung pausiert: nicht bestätigt', () async {
        api.knownDevices.add(phone);
        media.snapshot = snap(playing: false);
        withMedia();
        await expectLater(start(), throwsA(isA<PortException>()));
      });

      test('ohne Sitzungszugriff: Web-API (via=api)', () async {
        api.knownDevices.add(phone);
        media
          ..access = false
          ..snapshot = snap(playing: false);
        withMedia();
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(diag.last.$2['via'], 'api');
        expect(media.methodCalls, isNot(contains('nowPlaying')));
      });

      test('Fehler der Mediensitzung: zurück auf die Web-API, kein '
          'Abbruch', () async {
        api.knownDevices.add(phone);
        media.failNext('nowPlaying');
        withMedia();
        final r = await start();
        expect(r.confirmed, isTrue);
        expect(diag.last.$2['via'], 'api');
      });

      test('benanntes anderes Gerät: Web-API, Mediensitzung bleibt '
          'unberührt', () async {
        api.knownDevices.addAll([phone, speaker]);
        media.snapshot = snap(playing: false);
        withMedia();
        final r = await start(name: 'Wohnzimmer');
        expect(r.confirmed, isTrue);
        expect(r.isPhone, isFalse);
        expect(diag.last.$2['via'], 'api');
        expect(media.methodCalls, isEmpty);
      });
    });

    group('Handy lehnt den Befehl ab', () {
      setUp(() => api.knownDevices.add(phone));

      for (final (label, error) in [
        (
          '404',
          const PortException(
            PortErrorKind.notFound,
            'Spotify: nicht '
            'gefunden (HTTP 404)',
          ),
        ),
        (
          '5xx',
          const PortException(
            PortErrorKind.unavailable,
            'Spotify hat einen '
            'Serverfehler (HTTP 502)',
          ),
        ),
      ]) {
        test('$label: genau einmal wecken und wiederholen', () async {
          api
            ..rejectingDeviceIds.add('dev1')
            ..rejectStatus = error;
          launcher.onWake = api.rejectingDeviceIds.clear;
          final r = await start();
          expect(r.confirmed, isTrue);
          expect(launcher.wakes, 1);
          expect(count('play'), 2);
        });
      }

      test(
        'bleibt es abgelehnt: genau ein Wecken, der Fehler geht hoch',
        () async {
          api.rejectingDeviceIds.add('dev1');
          await expectLater(
            start(),
            throwsA(
              isA<PortException>()
                  .having((e) => e.kind, 'kind', PortErrorKind.notFound)
                  .having(
                    (e) => e.message,
                    'message',
                    allOf(contains('reagiert nicht'), isNot(contains('404'))),
                  ),
            ),
          );
          expect(launcher.wakes, 1);
          expect(count('play'), 2);
          // No verification polling for a phone that rejects commands.
          expect(count('playback'), 0);
        },
      );

      test('offline beim ersten Befehl: genau einmal wecken, dann der '
          'ehrliche Fehler', () async {
        api
          ..rejectingDeviceIds.add('dev1')
          ..rejectStatus = const PortException(
            PortErrorKind.unavailable,
            'Keine Verbindung',
          );
        await expectLater(
          start(),
          throwsA(
            isA<PortException>().having(
              (e) => e.message,
              'message',
              'Keine Verbindung',
            ),
          ),
        );
        expect(launcher.wakes, 1);
        expect(count('play'), 2);
        expect(count('playback'), 0);
      });

      test('ohne Launcher: der ursprüngliche Fehler', () async {
        api.rejectingDeviceIds.add('dev1');
        launcher.installed = false;
        await expectLater(start(), _port(PortErrorKind.notFound));
        expect(count('play'), 1);
      });

      test('429 und Berechtigung sind kein Weckgrund', () async {
        for (final error in [
          spotifyRateLimited,
          const PortException(PortErrorKind.rejected, 'verweigert'),
        ]) {
          api.failNext('play', error);
          await expectLater(start(), throwsA(same(error)));
        }
        expect(launcher.wakes, 0);
        expect(count('play'), 2);
      });

      test('anderes Gerät (nicht das Handy) lehnt ab: kein Wecken', () async {
        api
          ..knownDevices.add(speaker)
          ..rejectingDeviceIds.add('spk');
        await expectLater(
          start(name: 'Wohnzimmer'),
          _port(PortErrorKind.notFound),
        );
        expect(launcher.wakes, 0);
      });
    });

    test('eingeschränktes Gerät mit Handy-Namen wird nie Ziel', () async {
      api.knownDevices.add(
        const SpotifyDevice(
          id: 'r',
          name: 'Pixel 8',
          type: 'Smartphone',
          isRestricted: true,
        ),
      );
      host.hostNames = {'Pixel 8'};
      launcher.installed = false;
      await expectLater(start(), throwsA(same(spotifyNoDevice)));
      expect(count('play'), 0);
      launcher.installed = true;
      await expectLater(start(name: 'Pixel 8'), _port(PortErrorKind.notFound));
      expect(count('play'), 0);
    });

    test('Typregel: die ID wird nicht gemerkt, nur Namenstreffer', () async {
      const other = SpotifyDevice(id: 'x', name: 'Tablet', type: 'Smartphone');
      api.knownDevices.add(phone);
      await start();
      expect(diag.first.$2['via'], 'type');
      // A second smartphone appears: without a remembered id the type rule
      // no longer picks one (and nothing can wake the app).
      api.knownDevices.add(other);
      launcher.installed = false;
      await expectLater(start(), throwsA(same(spotifyNoDevice)));
    });

    test('Diagnose enthält weder Gerätenamen noch IDs', () async {
      api.knownDevices.add(phone);
      await start();
      final text = diag.map((e) => '${e.$1} ${e.$2}').join(' ');
      expect(text, isNot(contains('Pixel')));
      expect(text, isNot(contains('dev1')));
      expect(text, contains('target: phone'));
    });
  });
}
