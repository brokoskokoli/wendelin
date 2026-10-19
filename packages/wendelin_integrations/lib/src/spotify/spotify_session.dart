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
