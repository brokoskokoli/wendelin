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
    recovered = 0;
    waits = [];
    session = SpotifySession(
      api,
      secrets,
      launcher: launcher,
      clock: clock,
      onError: errors.add,
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
        session = SpotifySession(api, secrets, onError: errors.add);
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
    const phone = SpotifyDevice(id: 'dev1', name: 'Pixel 8');

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
}
