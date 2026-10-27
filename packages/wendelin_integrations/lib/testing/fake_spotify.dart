import '../src/common/port_exception.dart';
import '../src/spotify/spotify_api.dart';
import 'fake_failures.dart';

/// In-memory Spotify account for tests and the demo mode.
///
/// Tokens count up (`access-1`, …); [expireTokens] invalidates the current
/// access token (HTTP 401 on the next call), [revokeRefresh] the refresh
/// token. [premium] false makes commands fail like a free account, a
/// missing active device like Spotify (404). Failures can be injected per
/// method with [failNext] (`search`, `playback`, `devices`, `play`, `pause`,
/// `next`, `previous`, `queueAdd`, `exchangeCode`, `refresh`).
final class FakeSpotifyApi with FakeFailures implements SpotifyApi {
  /// Creates the fake.
  FakeSpotifyApi({
    this.premium = true,
    List<SpotifyItem>? catalog,
    List<SpotifyDevice>? devices,
  }) : catalog = catalog ?? defaultCatalog(),
       knownDevices = devices ?? [];

  /// A few items to search.
  static List<SpotifyItem> defaultCatalog() => const [
    SpotifyItem(
      kind: SpotifyKind.track,
      uri: 'spotify:track:4u7EnebtmKWzUH433cf5Qv',
      name: 'Bohemian Rhapsody',
      by: 'Queen',
    ),
    SpotifyItem(
      kind: SpotifyKind.track,
      uri: 'spotify:track:7hQJA50XrCWABAu5v6QZ4i',
      name: 'Somebody to Love',
      by: 'Queen',
    ),
    SpotifyItem(
      kind: SpotifyKind.album,
      uri: 'spotify:album:6X9k3iKZrQK3SDKpOZnB7M',
      name: 'A Night at the Opera',
      by: 'Queen',
    ),
    SpotifyItem(
      kind: SpotifyKind.artist,
      uri: 'spotify:artist:1dfeR4HaWDbWqFHLkxsg1d',
      name: 'Queen',
    ),
    SpotifyItem(
      kind: SpotifyKind.playlist,
      uri: 'spotify:playlist:37i9dQZF1DXcBWIGoYBM5M',
      name: 'This Is Queen',
      by: 'Spotify',
    ),
  ];

  /// Whether the account is Premium.
  bool premium;

  /// What a search can find.
  final List<SpotifyItem> catalog;

  /// Devices Spotify knows (mutable).
  final List<SpotifyDevice> knownDevices;

  /// Id of the device that is active, or `null`.
  String? activeDeviceId;

  /// Whether music is playing.
  bool playing = false;

  /// Runs after every accepted `play` (e.g. to inject a failure of the
  /// following state check).
  void Function()? onPlay;

  /// Devices that accept commands (Spotify answers 2xx) but never play, like
  /// a frozen app or a dead Connect device. A command to one makes it the
  /// active device and leaves [playing] false.
  final Set<String> frozenDeviceIds = {};

  /// Like Spotify for restricted or private devices: the playback state
  /// carries the device name but `device.id` is null.
  bool playbackWithoutDeviceId = false;

  /// Current track, context and position.
  String? trackUri;
  String? contextUri;
  int positionMs = 0;

  /// Title shown for the current track.
  String? title;

  /// Tracks added to the queue.
  final List<String> queue = [];

  /// Arguments of the last `play`.
  ({
    String? deviceId,
    List<String>? uris,
    String? contextUri,
    String? offsetUri,
    int? positionMs,
  })?
  lastPlay;

  /// Whether every token issue rotates the refresh token (`refresh-1`,
  /// `refresh-2`, …) and only the newest is accepted, like Spotify may do.
  bool rotateRefresh = false;

  int _tokenCounter = 0;
  String _access = '';
  bool _refreshRevoked = false;

  /// Codes the fake accepts at `exchangeCode`.
  static const validCode = 'code-1';

  /// The newest access token.
  String get currentAccess => _access;

  /// Invalidates the current access token.
  void expireTokens() => _access = 'expired';

  /// Rejects every refresh token from now on.
  void revokeRefresh() => _refreshRevoked = true;

  String _refreshToken = 'refresh-1';

  SpotifyAuth _issue(DateTime now) {
    _access = 'access-${++_tokenCounter}';
    if (rotateRefresh && _tokenCounter > 1) {
      _refreshToken = 'refresh-$_tokenCounter';
    }
    return SpotifyAuth(
      accessToken: _access,
      refreshToken: _refreshToken,
      expiresAt: now.add(const Duration(hours: 1)),
    );
  }

  /// The clock for issued tokens' expiry.
  DateTime Function() now = DateTime.now;

  void _check(SpotifyAuth auth) {
    if (auth.accessToken != _access) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Spotify-Sitzung abgelaufen oder abgelehnt (HTTP 401)',
      );
    }
  }

  void _command(SpotifyAuth auth, String method, String? deviceId) {
    enter(method);
    _check(auth);
    if (!premium) throw spotifyPremiumRequired;
    if (deviceId != null) {
      if (!knownDevices.any((d) => d.id == deviceId)) {
        throw spotifyNoDevice;
      }
      activeDeviceId = deviceId;
    } else if (activeDeviceId == null) {
      throw spotifyNoDevice;
    }
  }

  @override
  Future<SpotifyAuth> exchangeCode({
    required String clientId,
    required String code,
    required String verifier,
    required Uri redirect,
  }) async {
    enter('exchangeCode');
    if (code != validCode || verifier.length < 43) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Spotify-Anmeldung abgelehnt oder abgelaufen',
      );
    }
    return _issue(now());
  }

  @override
  Future<SpotifyAuth> refresh(String clientId, SpotifyAuth auth) async {
    enter('refresh');
    if (_refreshRevoked || auth.refreshToken != _refreshToken) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Spotify-Anmeldung abgelehnt oder abgelaufen',
      );
    }
    return _issue(now());
  }

  @override
  Future<List<SpotifyItem>> search(
    SpotifyAuth auth,
    String query,
    Set<SpotifyKind> kinds, {
    int limit = 5,
  }) async {
    enter('search');
    _check(auth);
    final words = query.toLowerCase().split(' ');
    return [
      for (final i in catalog)
        if (kinds.contains(i.kind) &&
            words.any((w) => i.label.toLowerCase().contains(w)))
          i,
    ];
  }

  @override
  Future<SpotifyPlayback?> playback(SpotifyAuth auth) async {
    enter('playback');
    _check(auth);
    if (activeDeviceId == null) return null;
    return SpotifyPlayback(
      isPlaying: playing,
      title: title,
      trackUri: trackUri,
      contextUri: contextUri,
      progressMs: positionMs,
      deviceName: knownDevices.firstWhere((d) => d.id == activeDeviceId).name,
      deviceId: playbackWithoutDeviceId ? null : activeDeviceId,
    );
  }

  @override
  Future<List<SpotifyDevice>> devices(SpotifyAuth auth) async {
    enter('devices');
    _check(auth);
    return [
      for (final d in knownDevices)
        SpotifyDevice(
          id: d.id,
          name: d.name,
          isActive: d.id == activeDeviceId,
          isRestricted: d.isRestricted,
          type: d.type,
        ),
    ];
  }

  @override
  Future<void> play(
    SpotifyAuth auth, {
    String? deviceId,
    List<String>? uris,
    String? contextUri,
    String? offsetUri,
    int? positionMs,
  }) async {
    _command(auth, 'play', deviceId);
    lastPlay = (
      deviceId: deviceId,
      uris: uris,
      contextUri: contextUri,
      offsetUri: offsetUri,
      positionMs: positionMs,
    );
    if (uris != null) {
      trackUri = uris.first;
      this.contextUri = null;
      title = catalog.where((i) => i.uri == trackUri).firstOrNull?.name;
    } else if (contextUri != null) {
      this.contextUri = contextUri;
      trackUri = offsetUri;
      title = catalog
          .where((i) => i.uri == (offsetUri ?? contextUri))
          .firstOrNull
          ?.name;
    }
    this.positionMs =
        positionMs ??
        (uris != null || contextUri != null ? 0 : this.positionMs);
    playing = !frozenDeviceIds.contains(activeDeviceId);
    onPlay?.call();
  }

  @override
  Future<void> pause(SpotifyAuth auth, {String? deviceId}) async {
    _command(auth, 'pause', deviceId);
    playing = false;
  }

  @override
  Future<void> next(SpotifyAuth auth, {String? deviceId}) async =>
      _command(auth, 'next', deviceId);

  @override
  Future<void> previous(SpotifyAuth auth, {String? deviceId}) async =>
      _command(auth, 'previous', deviceId);

  @override
  Future<void> queueAdd(
    SpotifyAuth auth,
    String uri, {
    String? deviceId,
  }) async {
    _command(auth, 'queueAdd', deviceId);
    queue.add(uri);
  }
}

/// [SpotifySecrets] in memory.
final class FakeSpotifySecrets implements SpotifySecrets {
  /// Creates the store; a logged-in state needs [clientId] and [auth].
  FakeSpotifySecrets({this.storedClientId, this.storedAuth});

  /// Current Client-ID.
  String? storedClientId;

  /// Current tokens.
  SpotifyAuth? storedAuth;

  @override
  Future<String?> clientId() async => storedClientId;

  @override
  Future<void> saveClientId(String? clientId) async =>
      storedClientId = clientId;

  @override
  Future<SpotifyAuth?> auth() async => storedAuth;

  @override
  Future<void> saveAuth(SpotifyAuth? auth) async => storedAuth = auth;
}

/// [SpotifyHostDevice] with fixed names.
final class FakeSpotifyHostDevice implements SpotifyHostDevice {
  /// Creates the port with the phone's [hostNames].
  FakeSpotifyHostDevice([this.hostNames = const {}]);

  /// Names of the phone.
  Set<String> hostNames;

  @override
  Future<Set<String>> names() async => hostNames;
}

/// [SpotifyAppLauncher] that counts wake-ups; [onWake] can make a device
/// appear, like the app starting.
final class FakeSpotifyLauncher implements SpotifyAppLauncher {
  /// Creates the launcher.
  FakeSpotifyLauncher({this.installed = true, this.onWake});

  /// Whether the app is installed.
  bool installed;

  /// Runs on every wake-up.
  void Function()? onWake;

  /// How often the app was woken.
  int wakes = 0;

  @override
  Future<bool> wake() async {
    if (!installed) return false;
    wakes++;
    onWake?.call();
    return true;
  }
}

/// [SpotifyAuthBrowser] that answers like Spotify's redirect: with [code]
/// and the `state` of the request, or with [error].
final class FakeSpotifyAuthBrowser implements SpotifyAuthBrowser {
  /// Creates the browser.
  FakeSpotifyAuthBrowser({
    this.code = FakeSpotifyApi.validCode,
    this.error,
    this.failure,
    this.stateOverride,
  });

  /// Code sent back.
  String? code;

  /// `error` parameter instead of a code.
  String? error;

  /// Thrown instead of a redirect (browser missing, user aborted).
  SpotifyBrowserFailure? failure;

  /// Wrong `state` to send back (attack simulation).
  String? stateOverride;

  /// Addresses opened so far.
  final List<Uri> opened = [];

  @override
  Future<Uri> authorize(Uri url, Uri redirect) async {
    opened.add(url);
    if (failure != null) throw SpotifyBrowserException(failure!);
    return redirect.replace(
      queryParameters: {
        'error': ?error,
        if (error == null && code != null) 'code': code!,
        'state': stateOverride ?? url.queryParameters['state']!,
      },
    );
  }
}
