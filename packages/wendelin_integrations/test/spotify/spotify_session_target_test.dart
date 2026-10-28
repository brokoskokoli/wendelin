import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _clientId = '0123456789abcdef0123456789abcdef';

Matcher _port(PortErrorKind kind) =>
    throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind));

void main() {
  const phone = SpotifyDevice(id: 'dev1', name: 'Pixel 8', type: 'Smartphone');
  const desktop = SpotifyDevice(id: 'pc', name: 'Büro-PC', type: 'Computer');
  const speaker = SpotifyDevice(id: 'spk', name: 'Wohnzimmer', type: 'Speaker');
  late FakeSpotifyApi api;
  late FakeSpotifyLauncher launcher;
  late List<Duration> waits;
  late List<(String, Map<String, Object>)> diag;
  late SpotifySession session;

  int count(String method) => api.methodCalls.where((m) => m == method).length;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 10, 18, 12));
    api = FakeSpotifyApi()..now = clock.now;
    final secrets = FakeSpotifySecrets(storedClientId: _clientId);
    secrets.storedAuth = await api.exchangeCode(
      clientId: _clientId,
      code: FakeSpotifyApi.validCode,
      verifier: 'v' * 64,
      redirect: spotifyRedirect,
    );
    api.methodCalls.clear();
    launcher = FakeSpotifyLauncher();
    waits = [];
    diag = [];
    session = SpotifySession(
      api,
      secrets,
      launcher: launcher,
      hostDevice: FakeSpotifyHostDevice(),
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

  void speakerPlays() => api
    ..knownDevices.addAll([phone, speaker])
    ..activeDeviceId = 'spk'
    ..playing = true;

  group('Zielwahl: dort weiterspielen, wo schon etwas läuft', () {
    test('spielendes Fremdgerät: der Befehl geht dorthin', () async {
      speakerPlays();
      final r = await start();
      expect(api.lastPlay!.deviceId, 'spk');
      expect(r.isPhone, isFalse);
      expect(r.confirmed, isTrue);
      expect(r.fellBackFrom, isNull);
      expect(launcher.wakes, 0);
      expect(
        diag.where((e) => e.$1 == 'spotify-device').first.$2['target'],
        'active',
      );
    });

    test('Fremdgerät pausiert: Handy', () async {
      api
        ..knownDevices.addAll([phone, speaker])
        ..activeDeviceId = 'spk'
        ..playing = false;
      final r = await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(r.isPhone, isTrue);
      expect(r.fellBackFrom, isNull);
      // Decided at once by `is_playing`, not by the stall check.
      expect(diag.any((e) => e.$2['skip'] != null), isFalse);
    });

    test('nichts aktiv: Handy', () async {
      api.knownDevices.addAll([phone, speaker]);
      final r = await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(r.isPhone, isTrue);
      expect(diag.first.$2['target'], 'phone');
    });

    test('spielt auf dem Handy selbst: normaler Handy-Pfad', () async {
      api
        ..knownDevices.addAll([phone, speaker])
        ..activeDeviceId = 'dev1'
        ..playing = true;
      final r = await start();
      expect(r.isPhone, isTrue);
      expect(r.fellBackFrom, isNull);
      expect(diag.where((e) => e.$2['skip'] != null), isEmpty);
    });

    test('spielend, aber Fortschritt steht (vorab): gleich Handy', () async {
      speakerPlays();
      api.stuckDeviceIds.add('spk');
      final r = await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(r.isPhone, isTrue);
      expect(r.fellBackFrom, isNull);
      expect(diag.any((e) => e.$2['skip'] == 'stalled'), isTrue);
      // Nothing was sent to the dead device.
      expect(count('play'), 1);
      expect(waits.first, SpotifySession.verifyInterval);
    });

    test('vorab ok, nach dem Befehl tot: Handy mit fellBackFrom', () async {
      speakerPlays();
      api.frozenDeviceIds.add('spk');
      final r = await start();
      expect(r.isPhone, isTrue);
      expect(r.confirmed, isTrue);
      expect(r.fellBackFrom, 'Wohnzimmer');
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(count('play'), 2);
      expect(diag.any((e) => e.$2['fallback'] == true), isTrue);
    });

    test('Fremdgerät lehnt den Befehl ab (404): Handy mit Hinweis', () async {
      speakerPlays();
      api.rejectingDeviceIds.add('spk');
      final r = await start();
      expect(r.fellBackFrom, 'Wohnzimmer');
      expect(r.isPhone, isTrue);
      expect(api.lastPlay!.deviceId, 'dev1');
    });

    test('Fremdgerät: Fehler ohne toten Zustand (rejected) bleibt', () async {
      speakerPlays();
      api.rejectingDeviceIds.add('spk');
      api.rejectStatus = const PortException(
        PortErrorKind.rejected,
        'Spotify: ungültig',
      );
      await expectLater(start(), _port(PortErrorKind.rejected));
      expect(count('play'), 1);
    });

    test('Lesefehler beim Vorab-Check: Handy', () async {
      speakerPlays();
      api.failNext(
        'playback',
        const PortException(PortErrorKind.unavailable, 'offline'),
      );
      final r = await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(r.isPhone, isTrue);
    });

    test('benanntes Gerät: dort, auch wenn ein anderes spielt', () async {
      api.knownDevices.addAll([phone, speaker, desktop]);
      api
        ..activeDeviceId = 'pc'
        ..playing = true;
      final r = await start(name: 'wohnzimmer');
      expect(api.lastPlay!.deviceId, 'spk');
      expect(r.fellBackFrom, isNull);
      expect(diag.first.$2['target'], 'named');
    });

    test('benanntes Gerät spielt nicht: Fehler, kein Ausweichen', () async {
      api
        ..knownDevices.addAll([phone, speaker])
        ..frozenDeviceIds.add('spk');
      await expectLater(
        start(name: 'wohnzimmer'),
        throwsA(isA<PortException>()),
      );
      expect(count('play'), 1);
    });

    test('eingeschränktes spielendes Gerät: Handy', () async {
      const locked = SpotifyDevice(
        id: 'lck',
        name: 'Gesperrt',
        type: 'Speaker',
        isRestricted: true,
      );
      api
        ..knownDevices.addAll([phone, locked])
        ..activeDeviceId = 'lck'
        ..playing = true;
      final r = await start();
      expect(api.lastPlay!.deviceId, 'dev1');
      expect(r.isPhone, isTrue);
    });

    test('Diagnose ohne Gerätenamen und IDs (auch beim Ausweichen)', () async {
      speakerPlays();
      api.frozenDeviceIds.add('spk');
      await start();
      final text = diag.map((e) => '${e.$1} ${e.$2}').join(' ');
      expect(text, isNot(contains('Wohnzimmer')));
      expect(text, isNot(contains('spk')));
    });
  });
}
