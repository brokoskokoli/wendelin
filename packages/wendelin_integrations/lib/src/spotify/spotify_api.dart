import 'package:meta/meta.dart';

import '../common/port_exception.dart';

/// Kinds of Spotify items the tools search and play.
enum SpotifyKind {
  /// A single song.
  track,

  /// An album.
  album,

  /// An artist (plays the artist's top tracks).
  artist,

  /// A playlist.
  playlist;

  /// The kind named by [name] (`track`, `album`, …), else `null`.
  static SpotifyKind? parse(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// A searchable and playable item.
@immutable
final class SpotifyItem {
  /// Creates an item.
  const SpotifyItem({
    required this.kind,
    required this.uri,
    required this.name,
    this.by,
  });

  /// What it is.
  final SpotifyKind kind;

  /// `spotify:track:…` and so on.
  final String uri;

  /// Title, album, artist or playlist name.
  final String name;

  /// Artists of a track or album, owner of a playlist.
  final String? by;

  /// Short German label, e.g. „Titel – Künstler“.
  String get label => by == null || by!.isEmpty ? name : '$name – $by';

  /// JSON for the model.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'name': name,
    if (by != null && by!.isNotEmpty) 'by': by,
    'uri': uri,
  };
}

/// Pattern of a playable Spotify URI (the only form the tools accept).
final spotifyUriPattern = RegExp(
  r'^spotify:(track|album|artist|playlist):[A-Za-z0-9]{10,40}$',
);

/// A Spotify Connect device.
@immutable
final class SpotifyDevice {
  /// Creates a device.
  const SpotifyDevice({
    required this.id,
    required this.name,
    this.isActive = false,
    this.isRestricted = false,
    this.type,
  });

  /// Device id for `device_id`.
  final String id;

  /// Display name, e.g. „Pixel 8“.
  final String name;

  /// Whether it is the active playback device.
  final bool isActive;

  /// Whether it cannot be controlled by the Web API.
  final bool isRestricted;

  /// Spotify's device type, e.g. `Smartphone`, `Computer`, `Speaker`.
  final String? type;
}

/// Names of the phone Wendelin runs on (e.g. device name, market name), to
/// recognise its Spotify Connect device.
abstract interface class SpotifyHostDevice {
  /// The names this phone may show up with in Spotify.
  Future<Set<String>> names();
}

/// The playback state (`GET /me/player`).
@immutable
final class SpotifyPlayback {
  /// Creates a state.
  const SpotifyPlayback({
    required this.isPlaying,
    this.title,
    this.by,
    this.album,
    this.trackUri,
    this.contextUri,
    this.progressMs,
    this.deviceName,
    this.deviceId,
  });

  /// Whether music is playing (not paused).
  final bool isPlaying;

  /// Current title (track or episode), if any.
  final String? title;

  /// Artists or show of [title].
  final String? by;

  /// Album of the track.
  final String? album;

  /// URI of the current track; `null` for episodes and unknown items.
  final String? trackUri;

  /// URI of the playlist, album or artist being played from.
  final String? contextUri;

  /// Position in the current title.
  final int? progressMs;

  /// Name of the device playing.
  final String? deviceName;

  /// Id of the device playing (`device.id`).
  final String? deviceId;

  /// JSON for the model.
  Map<String, Object?> toJson() => {
    'playing': isPlaying,
    if (title != null) 'title': title,
    if (by != null && by!.isNotEmpty) 'by': by,
    if (album != null && album!.isNotEmpty) 'album': album,
    if (deviceName != null) 'device': deviceName,
  };
}

/// Tokens of the Spotify login. Secrets: [toString] hides them, [toJson] is
/// only for the `SecretStore`.
@immutable
final class SpotifyAuth {
  /// Creates a session.
  const SpotifyAuth({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  /// Reads [toJson] output; `null` if fields are missing.
  static SpotifyAuth? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final access = json['accessToken'];
    final refresh = json['refreshToken'];
    final expires = json['expiresAt'];
    if (access is! String || refresh is! String || expires is! int) {
      return null;
    }
    return SpotifyAuth(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
    );
  }

  /// Bearer token of the Web API.
  final String accessToken;

  /// Token to get a new [accessToken].
  final String refreshToken;

  /// When [accessToken] ends.
  final DateTime expiresAt;

  /// Whether [accessToken] is still good at [now] (with a minute to spare).
  bool validAt(DateTime now) =>
      now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  /// For the `SecretStore` only.
  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  };

  @override
  String toString() => 'SpotifyAuth(<verborgen>)';
}

/// Where the Spotify secrets live (app: `SecretStore`): the user's own
/// Client-ID and the tokens. Never SQLite, settings JSON, logs or exports.
abstract interface class SpotifySecrets {
  /// The Client-ID of the user's Spotify developer app, or `null`.
  Future<String?> clientId();

  /// Replaces the Client-ID; `null` deletes it.
  Future<void> saveClientId(String? clientId);

  /// The stored tokens, or `null` when not logged in.
  Future<SpotifyAuth?> auth();

  /// Replaces the tokens; `null` deletes them.
  Future<void> saveAuth(SpotifyAuth? auth);
}

/// The Spotify Web API (and the token endpoint). Stateless: callers keep
/// the [SpotifyAuth].
///
/// Every method throws `PortException` only, with German texts that never
/// contain tokens or response bodies:
/// - `permissionDenied`: token or code rejected (401, `invalid_grant`),
/// - `notFound` with [spotifyNoDevice]: no active device (404),
/// - `rejected`: [spotifyPremiumRequired] or another refusal (403),
/// - `unavailable`: unreachable, timeout, 429, 5xx,
/// - `failed`: unexpected answer.
///
/// `HttpSpotifyApi` is tested against recorded responses, `FakeSpotifyApi`
/// is the in-memory twin for the tools.
abstract interface class SpotifyApi {
  /// Exchanges the login [code] for tokens (PKCE, no client secret).
  Future<SpotifyAuth> exchangeCode({
    required String clientId,
    required String code,
    required String verifier,
    required Uri redirect,
  });

  /// New tokens from [auth]'s refresh token (keeps the old refresh token if
  /// Spotify sends none).
  Future<SpotifyAuth> refresh(String clientId, SpotifyAuth auth);

  /// Searches [kinds]; at most [limit] hits per kind.
  Future<List<SpotifyItem>> search(
    SpotifyAuth auth,
    String query,
    Set<SpotifyKind> kinds, {
    int limit = 5,
  });

  /// The playback state, `null` when nothing is active.
  Future<SpotifyPlayback?> playback(SpotifyAuth auth);

  /// The devices Spotify knows (the app must have been opened once).
  Future<List<SpotifyDevice>> devices(SpotifyAuth auth);

  /// Starts [uris] (tracks) or [contextUri] (album, artist, playlist); with
  /// neither, resumes. [offsetUri] picks the track inside [contextUri]. [deviceId] targets (and wakes) that device.
  Future<void> play(
    SpotifyAuth auth, {
    String? deviceId,
    List<String>? uris,
    String? contextUri,
    String? offsetUri,
    int? positionMs,
  });

  /// Pauses.
  Future<void> pause(SpotifyAuth auth, {String? deviceId});

  /// Skips to the next title.
  Future<void> next(SpotifyAuth auth, {String? deviceId});

  /// Back to the previous title.
  Future<void> previous(SpotifyAuth auth, {String? deviceId});

  /// Appends the track [uri] to the queue.
  Future<void> queueAdd(SpotifyAuth auth, String uri, {String? deviceId});
}

/// No active device (Spotify: 404 `NO_ACTIVE_DEVICE`). Identity is checked
/// by `SpotifySession`.
const spotifyNoDevice = PortException(
  PortErrorKind.notFound,
  'Kein aktives Spotify-Gerät. Bitte die Spotify-App öffnen und einmal '
  'etwas abspielen.',
);

/// Spotify answered 429 or the client is blocked after one. Like all
/// `unavailable` errors, but the session never wakes the app for it.
const spotifyRateLimited = PortException(
  PortErrorKind.unavailable,
  'Spotify: Anfragelimit erreicht, später erneut versuchen',
);

/// The account is not Premium (Spotify: 403 `PREMIUM_REQUIRED`).
const spotifyPremiumRequired = PortException(
  PortErrorKind.rejected,
  'Die Wiedergabe steuern kann Spotify nur mit einem Premium-Konto.',
);

/// No tokens stored.
const spotifyNotLoggedIn = PortException(
  PortErrorKind.permissionDenied,
  'Spotify ist nicht angemeldet (Einstellungen → Integrationen → Spotify).',
);

/// Wakes the Spotify app when no device is active (app: `spotify:` intent).
abstract interface class SpotifyAppLauncher {
  /// Opens the Spotify app; `false` if it cannot be started (not installed).
  Future<bool> wake();
}

/// Why the browser step of the Spotify login did not return a redirect.
enum SpotifyBrowserFailure {
  /// No browser can show the login page.
  noBrowser,

  /// The user closed the browser without finishing.
  cancelled,

  /// An answer with another `state` than this login's arrived (stale tab,
  /// other app) and no matching one followed.
  stateMismatch,

  /// Any other failure.
  failed,
}

/// Thrown by [SpotifyAuthBrowser.authorize]; carries no text (the UI words it).
final class SpotifyBrowserException implements Exception {
  /// Creates the exception.
  const SpotifyBrowserException(this.failure);

  /// What went wrong.
  final SpotifyBrowserFailure failure;

  @override
  String toString() => 'SpotifyBrowserException(${failure.name})';
}

/// Shows the Spotify login page and returns the redirect (app: Custom Tab).
abstract interface class SpotifyAuthBrowser {
  /// Opens [url] and completes with the redirect to [redirect]. Throws a
  /// [SpotifyBrowserException] if there is no browser or the user aborts.
  Future<Uri> authorize(Uri url, Uri redirect);
}
