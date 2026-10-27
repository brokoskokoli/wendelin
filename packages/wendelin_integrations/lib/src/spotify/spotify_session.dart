import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import 'spotify_api.dart';

/// Waits [d] (injectable so tests do not sleep).
typedef SpotifyDelay = Future<void> Function(Duration d);

/// Token handling, device wake-up and error state of the Spotify tools.
///
/// Every API call runs through [run]: the tokens come from memory, then
/// from [SpotifySecrets]; an expired access token is renewed first, a
/// rejected one (HTTP 401) **once** and the call repeated once (a 401 means
/// the call was not applied, so this is safe for commands too). When the
/// renewal is refused (login revoked), the tokens are dropped and [onError]
/// pauses the integration. A 401 after a successful renewal (e.g. a missing
/// scope) also pauses it and advises logging in again, but keeps the tokens.
/// Temporary failures (offline, 429, 5xx) only fail
/// the call.
///
/// [playbackCommand] adds the device logic: with no active device it picks a
/// known one or, for commands that start music, wakes the Spotify app
/// ([SpotifyAppLauncher]) and polls for its device.
final class SpotifySession {
  /// Creates the session.
  SpotifySession(
    this.api,
    this.secrets, {
    this.launcher,
    this.hostDevice,
    this.onDiagnostic,
    this.onError,
    this.onRecovered,
    this._clock = const SystemClock(),
    SpotifyDelay? delay,
  }) : _delay = delay ?? (Future<void>.delayed);

  /// The Web API.
  final SpotifyApi api;

  /// Client-ID and tokens.
  final SpotifySecrets secrets;

  /// Wakes the Spotify app; `null` if the platform cannot.
  final SpotifyAppLauncher? launcher;

  /// Names of this phone, to find its Connect device; optional.
  final SpotifyHostDevice? hostDevice;

  /// Diagnostics (`spotify-device`, `spotify-verify`) without titles, URIs,
  /// device names or tokens.
  final void Function(String event, Map<String, Object> fields)? onDiagnostic;

  /// Called with a German message when the integration must show „Fehler“.
  final void Function(String message, PortErrorKind kind)? onError;

  /// Called when a call succeeds after [onError].
  final void Function()? onRecovered;

  final Clock _clock;
  final SpotifyDelay _delay;

  /// Polls for the device after waking the app.
  static const wakeAttempts = 5;

  /// Pause between those polls.
  static const wakeInterval = Duration(seconds: 2);

  /// How often [startPlayback] looks at the playback state.
  static const verifyAttempts = 3;

  /// Wait before each of those looks.
  static const verifyInterval = Duration(seconds: 1);

  /// Id of the phone's device once recognised (memory only).
  String? _phoneId;

  SpotifyAuth? _auth;
  Future<SpotifyAuth>? _renewing;
  bool _failed = false;

  /// Whether the last failure put the integration into the error state and
  /// no call has succeeded since.
  bool get failed => _failed;

  /// Runs [op] with a valid access token (see the class comment).
  Future<T> run<T>(Future<T> Function(SpotifyAuth auth) op) async {
    // Only a rejected refresh proves the login is gone; a 401 after a
    // successful refresh (e.g. a missing scope) keeps the tokens.
    var refreshRejected = false;
    Future<SpotifyAuth> renew(SpotifyAuth stale) async {
      try {
        return await _renew(stale);
      } on PortException catch (e) {
        if (e.kind == PortErrorKind.permissionDenied) refreshRejected = true;
        rethrow;
      }
    }

    try {
      var auth = await _current();
      if (!auth.validAt(_clock.now())) auth = await renew(auth);
      T result;
      try {
        result = await op(auth);
      } on PortException catch (e) {
        if (e.kind != PortErrorKind.permissionDenied) rethrow;
        result = await op(await renew(auth));
      }
      if (_failed) {
        _failed = false;
        onRecovered?.call();
      }
      return result;
    } on PortException catch (e) {
      if (identical(e, spotifyNotLoggedIn)) rethrow;
      if (e.kind == PortErrorKind.permissionDenied) {
        if (refreshRejected) await _drop();
        _failed = true;
        final msg = refreshRejected
            ? 'Spotify-Anmeldung abgelaufen'
            : 'Spotify verweigert den Zugriff';
        onError?.call(msg, e.kind);
        throw PortException(
          e.kind,
          '$msg. Bitte unter Einstellungen → Integrationen → Spotify neu '
          'anmelden.',
        );
      }
      rethrow;
    }
  }

  /// Runs a playback command. With no active device: a known device is used
  /// (`deviceId` set); if there is none and [wake] is true, the Spotify app
  /// is started and its device awaited. Throws [spotifyNoDevice] otherwise.
  Future<T> playbackCommand<T>(
    Future<T> Function(SpotifyAuth auth, String? deviceId) op, {
    bool wake = false,
  }) async {
    try {
      return await run((a) => op(a, null));
    } on PortException catch (e) {
      if (!identical(e, spotifyNoDevice) || !wake) rethrow;
    }
    final id = await _findDevice();
    if (id == null) throw spotifyNoDevice;
    return run((a) => op(a, id));
  }

  /// Starts music (`op` gets the target's id) and checks that it plays.
  ///
  /// The target is the phone (see [_phone]) or, if [deviceName] is given, the
  /// device of that name. The command always carries the target's `device_id`.
  /// The state is read up to [verifyAttempts] times; success needs
  /// `isPlaying` on the target. If the phone does not play, the Spotify app
  /// is woken **once** and the command repeated; a failed check (429,
  /// offline) ends at once with `confirmed == false`.
  /// Throws [spotifyNoDevice] (no phone device, app not wakeable) and a
  /// [PortException] with an honest text if nothing plays.
  Future<SpotifyStart> startPlayback(
    Future<void> Function(SpotifyAuth auth, String deviceId) op, {
    String? deviceName,
  }) async {
    var usable = await _usable();
    var woke = false;
    SpotifyDevice target;
    var phone = await _phone(usable);
    if (deviceName != null) {
      final found = _byName(usable, deviceName);
      if (found == null) {
        final names = usable.map((d) => d.name).join(', ');
        throw PortException(
          PortErrorKind.notFound,
          'Spotify kennt kein Gerät „$deviceName“. '
          'Verfügbar: ${names.isEmpty ? 'keins' : names}.',
        );
      }
      target = found;
      _diagnose('spotify-device', 'named', 'name', woke, usable.length);
    } else {
      if (phone == null) {
        if (!await _wake()) throw spotifyNoDevice;
        woke = true;
        phone = await _waitForPhone();
        if (phone == null) throw spotifyNoDevice;
        usable = await _usable();
      }
      target = phone.device;
      _diagnose('spotify-device', 'phone', phone.via, woke, usable.length);
    }
    final isPhone = deviceName == null || target.id == phone?.device.id;

    await run((a) => op(a, target.id));
    var result = await _verify(target.id);
    if (result == _Verify.unchecked) {
      return (
        deviceId: target.id,
        deviceName: target.name,
        isPhone: isPhone,
        confirmed: false,
      );
    }
    if (result != _Verify.playing && isPhone && !woke && await _wake()) {
      woke = true;
      final again = await _waitForPhone();
      if (again != null) {
        _diagnose('spotify-device', 'phone', again.via, woke, usable.length);
        target = again.device;
        try {
          await run((a) => op(a, target.id));
        } on PortException catch (e) {
          if (e.kind != PortErrorKind.notFound) rethrow;
        }
        result = await _verify(target.id);
        if (result == _Verify.unchecked) {
          return (
            deviceId: target.id,
            deviceName: target.name,
            isPhone: true,
            confirmed: false,
          );
        }
      }
    }
    if (result != _Verify.playing) {
      throw PortException(
        PortErrorKind.failed,
        isPhone
            ? 'Spotify hat den Befehl angenommen, aber auf dem Handy läuft '
                  'nichts. Die Spotify-App reagiert nicht; bitte Spotify '
                  'einmal selbst öffnen und dann noch einmal versuchen.'
            : 'Spotify hat den Befehl angenommen, aber auf dem Gerät '
                  '„${target.name}“ läuft nichts.',
      );
    }
    return (
      deviceId: target.id,
      deviceName: target.name,
      isPhone: isPhone,
      confirmed: true,
    );
  }

  Future<List<SpotifyDevice>> _usable() async => [
    for (final d in await run(api.devices))
      if (!d.isRestricted) d,
  ];

  Future<bool> _wake() async => launcher != null && await launcher!.wake();

  Future<({SpotifyDevice device, String via})?> _waitForPhone() async {
    for (var i = 0; i < wakeAttempts; i++) {
      await _delay(wakeInterval);
      final found = await _phone(await _usable());
      if (found != null) return found;
    }
    return null;
  }

  Future<_Verify> _verify(String deviceId) async {
    var result = _Verify.idle;
    var attempts = 0;
    for (var i = 0; i < verifyAttempts; i++) {
      await _delay(verifyInterval);
      attempts++;
      SpotifyPlayback? state;
      try {
        state = await run(api.playback);
      } on PortException catch (e) {
        if (e.kind == PortErrorKind.permissionDenied) rethrow;
        result = _Verify.unchecked;
        break;
      }
      if (state != null && state.isPlaying) {
        result = state.deviceId == deviceId
            ? _Verify.playing
            : _Verify.otherDevice;
      } else {
        result = _Verify.idle;
      }
      if (result == _Verify.playing) break;
    }
    onDiagnostic?.call('spotify-verify', {
      'result': result.label,
      'attempts': attempts,
    });
    return result;
  }

  void _diagnose(String event, String target, String via, bool woke, int n) =>
      onDiagnostic?.call(event, {
        'target': target,
        'via': via,
        'woke': woke,
        'devices': n,
      });

  static SpotifyDevice? _byName(List<SpotifyDevice> devices, String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    for (final d in devices) {
      if (d.name.trim().toLowerCase() == wanted) return d;
    }
    for (final d in devices) {
      if (d.name.toLowerCase().contains(wanted)) return d;
    }
    return null;
  }

  /// The phone's device among [usable]: the remembered id, a name of the
  /// phone, or the only smartphone.
  Future<({SpotifyDevice device, String via})?> _phone(
    List<SpotifyDevice> usable,
  ) async {
    ({SpotifyDevice device, String via})? found;
    final cached = usable.where((d) => d.id == _phoneId).firstOrNull;
    if (cached != null) {
      found = (device: cached, via: 'cache');
    } else {
      Set<String> names = const {};
      try {
        names = {
          for (final n in await hostDevice?.names() ?? const <String>{})
            n.trim().toLowerCase(),
        }..remove('');
      } on Object {
        // Names are optional help; the type rule still applies.
      }
      final byName = usable
          .where((d) => names.contains(d.name.trim().toLowerCase()))
          .firstOrNull;
      if (byName != null) {
        found = (device: byName, via: 'name');
      } else {
        final phones = usable
            .where((d) => d.type?.toLowerCase() == 'smartphone')
            .toList();
        if (phones.length == 1) found = (device: phones.single, via: 'type');
      }
    }
    if (found != null) _phoneId = found.device.id;
    return found;
  }

  Future<String?> _findDevice() async {
    var id = await _pick();
    if (id != null) return id;
    if (launcher == null || !await launcher!.wake()) return null;
    for (var i = 0; i < wakeAttempts && id == null; i++) {
      await _delay(wakeInterval);
      id = await _pick();
    }
    return id;
  }

  Future<String?> _pick() async {
    final devices = await run(api.devices);
    final usable = devices.where((d) => !d.isRestricted).toList();
    if (usable.isEmpty) return null;
    return usable.firstWhere((d) => d.isActive, orElse: () => usable.first).id;
  }

  /// Forgets the tokens in memory (e.g. after the login changed).
  Future<void> forget() async {
    _auth = null;
  }

  Future<void> _drop() async {
    _auth = null;
    await secrets.saveAuth(null);
  }

  Future<SpotifyAuth> _current() async {
    final cached = _auth ??= await secrets.auth();
    if (cached == null) throw spotifyNotLoggedIn;
    return cached;
  }

  /// New tokens replacing [stale]; parallel callers share one renewal.
  Future<SpotifyAuth> _renew(SpotifyAuth stale) {
    final current = _auth;
    // Dropped meanwhile (login rejected): never renew with the stale token.
    if (current == null) return Future.error(spotifyNotLoggedIn);
    if (current != stale) return Future.value(current);
    return _renewing ??= _doRenew(stale).whenComplete(() => _renewing = null);
  }

  Future<SpotifyAuth> _doRenew(SpotifyAuth stale) async {
    final clientId = await secrets.clientId();
    if (clientId == null) throw spotifyNotLoggedIn;
    final fresh = await api.refresh(clientId, stale);
    _auth = fresh;
    await secrets.saveAuth(fresh);
    return fresh;
  }
}

/// Outcome of [SpotifySession.startPlayback]: the device it targeted, whether
/// that is the phone and whether playback was seen on it.
typedef SpotifyStart = ({
  String deviceId,
  String deviceName,
  bool isPhone,
  bool confirmed,
});

enum _Verify {
  playing('playing'),
  idle('idle'),
  otherDevice('other-device'),
  unchecked('unchecked');

  const _Verify(this.label);
  final String label;
}
