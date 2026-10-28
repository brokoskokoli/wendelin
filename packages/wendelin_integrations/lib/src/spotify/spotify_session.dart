import 'package:wendelin_core/wendelin_core.dart';

import '../common/port_exception.dart';
import '../media/media_port.dart';
import 'spotify_api.dart';
import 'spotify_playback_verifier.dart';

part 'spotify_session_devices.dart';

/// Android package of the Spotify app (wake-up, app detection, media
/// session check).
const spotifyAndroidPackage = 'com.spotify.music';

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
    this.media,
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

  /// The phone's media sessions: with notification access, Spotify's own
  /// session proves that the phone plays (a dead Connect device may still
  /// show `is_playing` in the Web API); optional.
  final MediaControlPort? media;

  /// Diagnostics (`spotify-device`, `spotify-verify`) without titles, URIs,
  /// device names or tokens.
  final void Function(String event, Map<String, Object> fields)? onDiagnostic;

  /// Called with a German message when the integration must show „Fehler“.
  final void Function(String message, PortErrorKind kind)? onError;

  /// Called when a call succeeds after [onError].
  final void Function()? onRecovered;

  final Clock _clock;
  final SpotifyDelay _delay;

  late final _verifier = SpotifyPlaybackVerifier(
    api: api,
    run: run,
    media: media,
    delay: _delay,
    maxAttempts: verifyAttempts,
    foreignMaxAttempts: foreignVerifyAttempts,
    interval: verifyInterval,
    onDiagnostic: onDiagnostic,
  );

  /// Polls for the device after waking the app.
  static const wakeAttempts = 5;

  /// Pause between those polls.
  static const wakeInterval = Duration(seconds: 2);

  /// How often [startPlayback] looks at the playback state.
  static const verifyAttempts = 3;

  /// The same for a foreign device (about 10 s): cast devices report the
  /// new position late, so a slow start is not "nothing arrived".
  static const foreignVerifyAttempts = 10;

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
  /// The target is the named device; else the device on which something plays
  /// right now (checked twice, see [_playingElsewhere]; if nothing arrives
  /// there because the command fails with a dead-device error, the phone
  /// takes over, `fellBackFrom` set; a command that is accepted but not
  /// confirmed within [foreignVerifyAttempts] stays there, `confirmed ==
  /// false`); else the phone (see
  /// [_phone]). The command always carries the target's `device_id`.
  /// The state is read up to [verifyAttempts] times (foreign device:
  /// [foreignVerifyAttempts]; see [_verify]: for the
  /// phone with notification access Spotify's media session must be playing,
  /// else the Web API must show the target playing with a growing position).
  /// If the phone does not play, or rejects the command (404, 5xx: frozen
  /// app), the Spotify app is woken **once** and the command repeated; a
  /// failed check (429, offline) ends at once with `confirmed == false`.
  /// Throws [spotifyNoDevice] (no phone device, app not wakeable) and a
  /// [PortException] with an honest text if nothing plays.
  Future<SpotifyStart> startPlayback(
    Future<void> Function(SpotifyAuth auth, String deviceId) op, {
    String? deviceName,
    bool preferActive = true,
    String? fellBackFrom,
  }) async {
    final chosen = await _choose(deviceName, preferActive: preferActive);
    var target = chosen.target;
    var woke = chosen.woke;
    final isPhone = chosen.isPhone;
    SpotifyStart done(bool confirmed) => (
      deviceId: target.id,
      deviceName: target.name,
      isPhone: isPhone,
      confirmed: confirmed,
      fellBackFrom: fellBackFrom,
    );

    if (chosen.isActive) {
      final played = await _playOnActive(op, target, fellBackFrom);
      return played ??
          startPlayback(op, preferActive: false, fellBackFrom: target.name);
    }

    // A phone that is listed but rejects the command is treated like one
    // that does not play (429, 401/403 and the like are not).
    PortException? rejection;
    try {
      await run((a) => op(a, target.id));
    } on PortException catch (e) {
      if (!isPhone || woke || !_deadDevice(e)) rethrow;
      rejection = e;
    }
    var result = rejection != null
        ? SpotifyVerdict.idle
        : await _verifier.check(target, isPhone);
    if (result == SpotifyVerdict.unchecked) return done(false);
    if (result != SpotifyVerdict.playing && isPhone && !woke && await _wake()) {
      woke = true;
      final again = await _waitForPhone();
      if (again != null) {
        _diagnose('spotify-device', 'phone', again.via, woke, chosen.count);
        target = again.device;
        rejection = null;
        try {
          await run((a) => op(a, target.id));
        } on PortException catch (e) {
          if (e.kind != PortErrorKind.notFound) rethrow;
          rejection = e;
        }
        if (rejection != null) {
          // Still rejected after waking: no checks, say what is wrong.
          throw PortException(
            rejection.kind,
            'Spotify auf dem Handy reagiert nicht. Bitte die Spotify-App '
            'einmal selbst öffnen (und prüfen, dass sie im Hintergrund '
            'laufen darf, Akku-Ausnahme).',
          );
        }
        result = await _verifier.check(target, isPhone);
        if (result == SpotifyVerdict.unchecked) return done(false);
      }
    }
    if (result != SpotifyVerdict.playing) {
      // The phone rejected the command and could not be woken.
      if (rejection != null) throw rejection;
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
    return done(true);
  }

  /// The target of [startPlayback]: the named device, else the phone (the
  /// app is woken once if the phone is not listed).
  Future<
    ({SpotifyDevice target, bool isPhone, bool woke, int count, bool isActive})
  >
  _choose(String? deviceName, {bool preferActive = true}) async {
    var usable = await _usable();
    var phone = await _phone(usable);
    if (deviceName != null) {
      final found = _SpotifyDevices._byName(usable, deviceName);
      if (found == null) {
        final names = usable.map((d) => d.name).join(', ');
        throw PortException(
          PortErrorKind.notFound,
          'Spotify kennt kein Gerät „$deviceName“. '
          'Verfügbar: ${names.isEmpty ? 'keins' : names}.',
        );
      }
      _diagnose('spotify-device', 'named', 'name', false, usable.length);
      return (
        target: found,
        isPhone: found.id == phone?.device.id,
        woke: false,
        count: usable.length,
        isActive: false,
      );
    }
    if (preferActive) {
      final active = await _playingElsewhere(usable, phone?.device.id);
      if (active != null) {
        _diagnose('spotify-device', 'active', 'playback', false, usable.length);
        return (
          target: active,
          isPhone: false,
          woke: false,
          count: usable.length,
          isActive: true,
        );
      }
    }
    var woke = false;
    if (phone == null) {
      if (!await _wake()) throw spotifyNoDevice;
      woke = true;
      phone = await _waitForPhone();
      if (phone == null) throw spotifyNoDevice;
      usable = await _usable();
    }
    _diagnose('spotify-device', 'phone', phone.via, woke, usable.length);
    return (
      target: phone.device,
      isPhone: true,
      woke: woke,
      count: usable.length,
      isActive: false,
    );
  }

  /// 404 (device gone) or a server error: the listed device does not work.
  /// 429 (`spotifyRateLimited`), offline-independent auth errors and the like
  /// are not a reason to wake the app.
  static bool _deadDevice(PortException e) =>
      e.kind == PortErrorKind.notFound ||
      (e.kind == PortErrorKind.unavailable &&
          !identical(e, spotifyRateLimited));

  void _diagnose(String event, String target, String via, bool woke, int n) =>
      onDiagnostic?.call(event, {
        'target': target,
        'via': via,
        'woke': woke,
        'devices': n,
      });

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
/// that is the phone and whether playback was seen on it. [fellBackFrom] is
/// the name of the playing device that got nothing, when the phone took over.
typedef SpotifyStart = ({
  String deviceId,
  String deviceName,
  bool isPhone,
  bool confirmed,
  String? fellBackFrom,
});
