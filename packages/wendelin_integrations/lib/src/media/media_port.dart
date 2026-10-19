/// Android package of the Audible app (`media__open_audible`).
const audiblePackage = 'com.audible.application';

/// A transport command for the active media player.
enum MediaCommand {
  /// Start or resume playback.
  play,

  /// Pause playback.
  pause,

  /// Next track or chapter.
  next,

  /// Previous track or chapter.
  previous,
}

/// What the active media session reports right now.
final class MediaSnapshot {
  /// Creates a snapshot.
  const MediaSnapshot({
    required this.packageName,
    required this.appName,
    required this.playing,
    this.title,
    this.artist,
    this.album,
    this.positionMs,
    this.durationMs,
  });

  /// Package of the player app.
  final String packageName;

  /// Name of the player app for the UI.
  final String appName;

  /// Whether the player is playing (not paused or stopped).
  final bool playing;

  /// Title of the track, episode or book, if the player tells it.
  final String? title;

  /// Artist, author or podcast, if known.
  final String? artist;

  /// Album or series, if known.
  final String? album;

  /// Current position in milliseconds (already extrapolated while
  /// playing), `null` if unknown.
  final int? positionMs;

  /// Length in milliseconds, `null` if unknown (e.g. a live stream).
  final int? durationMs;
}

/// The active media player of the device (any app that publishes a media
/// session: Audible, podcast apps, Spotify, YouTube Music, …).
///
/// Android: reading sessions and seeking needs the notification access
/// (`NotificationListenerService`), see [hasSessionAccess]. Transport
/// commands also work without it through media key events (fallback), but
/// then nothing can be read back. Failures throw `PortException` with a
/// short German text: no access (`permissionDenied`), no player
/// (`notFound`), player cannot seek (`unsupported`). Must pass
/// `mediaControlPortContract`.
abstract interface class MediaControlPort {
  /// Whether the notification access (needed to read sessions) is granted.
  Future<bool> hasSessionAccess();

  /// Opens the system page where the user grants the notification access.
  Future<void> openSessionAccessSettings();

  /// The session that is playing, else the most recent one; `null` if
  /// there is none. Throws `permissionDenied` without access.
  Future<MediaSnapshot?> nowPlaying();

  /// Sends [command] to the active player. Uses the session if there is
  /// access, else a media key event (no feedback whether anybody listened).
  Future<void> send(MediaCommand command);

  /// Jumps to [position] in the active player. Needs access
  /// (`permissionDenied`), a session (`notFound`) and a seekable player
  /// (`unsupported`).
  Future<void> seekTo(Duration position);

  /// Opens the app [androidPackage]; with [searchQuery] it tries a media
  /// search in that app first and opens the app plain if it does not
  /// handle it. Throws `notFound` if the app is not installed.
  Future<void> openApp(String androidPackage, {String? searchQuery});
}
