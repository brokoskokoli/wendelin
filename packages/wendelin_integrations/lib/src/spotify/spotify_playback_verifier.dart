import '../common/port_exception.dart';
import '../media/media_port.dart';
import 'spotify_api.dart';
import 'spotify_session.dart' show SpotifyDelay, spotifyAndroidPackage;

/// Checks that a started playback really plays (see [check]).
final class SpotifyPlaybackVerifier {
  /// Creates the verifier; [run] adds the token handling to an API call.
  SpotifyPlaybackVerifier({
    required this.api,
    required this.run,
    required this.delay,
    required this.maxAttempts,
    int? foreignMaxAttempts,
    required this.interval,
    this.media,
    this.onDiagnostic,
  }) : foreignMaxAttempts = foreignMaxAttempts ?? maxAttempts;

  /// The Web API.
  final SpotifyApi api;

  /// Runs an API call with the session's tokens.
  final Future<T> Function<T>(Future<T> Function(SpotifyAuth auth) op) run;

  /// The phone's media sessions, if available.
  final MediaControlPort? media;

  /// Waits between the looks.
  final SpotifyDelay delay;

  /// How often the state is read.
  final int maxAttempts;

  /// How often the state is read for a foreign device (cast devices report
  /// `progress_ms` late); the phone uses [maxAttempts].
  final int foreignMaxAttempts;

  /// Wait before each look.
  final Duration interval;

  /// Diagnostics without titles, URIs, device names or tokens.
  final void Function(String event, Map<String, Object> fields)? onDiagnostic;

  /// Looks up to [maxAttempts] times ([foreignMaxAttempts] if not [isPhone])
  /// whether [target] plays.
  ///
  /// For the phone with notification access: Spotify's own media session
  /// (`com.spotify.music`) must be playing (`via=session`). Otherwise the
  /// Web API must show the target playing and `progress_ms` growing between
  /// two reads (`via=api`): `is_playing` alone also appears for a dead
  /// device. A failing media session falls back to the Web API.
  Future<SpotifyVerdict> check(SpotifyDevice target, bool isPhone) async {
    var result = SpotifyVerdict.idle;
    var attempts = 0;
    var via = 'api';
    if (isPhone && media != null) {
      try {
        if (await media!.hasSessionAccess()) via = 'session';
      } on PortException {
        // Web API only.
      }
    }
    int? lastProgress;
    final progress = <String>[];
    var otherApp = false;
    final limit = isPhone ? maxAttempts : foreignMaxAttempts;
    for (var i = 0; i < limit; i++) {
      await delay(interval);
      attempts++;
      if (via == 'session') {
        try {
          final snap = await media!.nowPlaying();
          if (snap != null &&
              snap.playing &&
              snap.packageName != spotifyAndroidPackage) {
            // Another app is the active session: this says nothing about
            // Spotify, so the Web API decides (and nothing is woken).
            otherApp = true;
            via = 'api';
          } else {
            result =
                snap != null &&
                    snap.packageName == spotifyAndroidPackage &&
                    snap.playing
                ? SpotifyVerdict.playing
                : SpotifyVerdict.idle;
            if (result == SpotifyVerdict.playing) break;
            continue;
          }
        } on PortException {
          via = 'api';
        }
      }
      SpotifyPlayback? state;
      try {
        state = await run(api.playback);
      } on PortException catch (e) {
        if (e.kind == PortErrorKind.permissionDenied) rethrow;
        result = SpotifyVerdict.unchecked;
        break;
      }
      progress.add(_progressSecond(state));
      (result, lastProgress) = _classify(state, target, lastProgress);
      if (result == SpotifyVerdict.playing) break;
    }
    // Another app plays and the Web API does not confirm Spotify: not
    // proven either way, so neither wake nor restart.
    if (otherApp && result != SpotifyVerdict.playing) {
      result = SpotifyVerdict.unchecked;
    }
    onDiagnostic?.call('spotify-verify', {
      'result': result.label,
      'via': via,
      'attempts': attempts,
      if (progress.isNotEmpty) 'progress': progress.join(','),
    });
    return result;
  }

  /// Progress of one read in whole seconds, `-` if nothing plays or the
  /// position is missing (no titles, URIs or names).
  static String _progressSecond(SpotifyPlayback? state) {
    final p = state != null && state.isPlaying ? state.progressMs : null;
    return p == null ? '-' : '${p ~/ 1000}';
  }

  /// Verdict for one read and the new base position. Equal or smaller
  /// progress (the position jumps back to 0 when the new track starts, cast
  /// devices first report the old one) is not yet proof: stalled, and the
  /// base restarts there.
  static (SpotifyVerdict, int?) _classify(
    SpotifyPlayback? state,
    SpotifyDevice target,
    int? lastProgress,
  ) {
    if (state == null || !state.isPlaying) return (SpotifyVerdict.idle, null);
    if (!_isTarget(state, target)) return (SpotifyVerdict.otherDevice, null);
    final p = state.progressMs;
    if (lastProgress != null && p != null && p > lastProgress) {
      return (SpotifyVerdict.playing, lastProgress);
    }
    return (SpotifyVerdict.stalled, p);
  }

  /// Spotify may send `device.id: null` (restricted or private devices);
  /// then only the device name can tell whether [state] is on [target].
  static bool _isTarget(SpotifyPlayback state, SpotifyDevice target) {
    final id = state.deviceId;
    if (id != null) return id == target.id;
    final name = state.deviceName?.trim().toLowerCase();
    return name != null &&
        name.isNotEmpty &&
        name == target.name.trim().toLowerCase();
  }
}

/// Result of one playback check.
enum SpotifyVerdict {
  playing('playing'),
  idle('idle'),
  otherDevice('other-device'),
  stalled('stalled'),
  unchecked('unchecked');

  const SpotifyVerdict(this.label);
  final String label;
}
