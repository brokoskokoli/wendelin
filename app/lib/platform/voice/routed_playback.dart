import 'dart:async';

import 'audio_track_playback.dart';
import 'pcm.dart';
import 'sherpa_tts.dart';

/// Chooses the output path per [play] (WP188): without a chosen device
/// ([hasChoice] false: "System", also while the choice is still loading or
/// unreadable) everything runs on [system] exactly as before, without an
/// extra await. With a chosen device ([hasChoice] true, even if it is
/// missing right now) the native `AudioTrack` plays, so a device coming and
/// going during the clip is followed by the native side. A choice changed
/// during a clip applies from the next [play].
///
/// If the native side is not there (an engine without the channel) or the
/// track cannot be created, that clip plays on [system] instead.
final class RoutedPlayback implements AudioPlayback {
  /// Creates the router.
  RoutedPlayback({
    required this.system,
    required this.track,
    required this.hasChoice,
  });

  /// Path without a choice.
  final AudioPlayback system;

  /// Path with a chosen device.
  final AudioPlayback track;

  /// Whether a device is chosen for the output (read on every play).
  final bool Function() hasChoice;

  AudioPlayback? _active;
  var _generation = 0;

  @override
  Future<void> play(Wav wav) async {
    final generation = ++_generation;
    var choice = false;
    try {
      choice = hasChoice();
    } on Object {
      // Unreadable choice: system.
    }
    final target = choice ? track : system;
    final previous = _active;
    // Only when the path changes the old clip is stopped here; otherwise
    // the player replaces it itself and there is no extra await.
    if (previous != null && !identical(previous, target)) {
      await previous.stop();
      if (generation != _generation) return;
    }
    _active = target;
    if (!identical(target, track)) return system.play(wav);
    try {
      await track.play(wav);
    } on AudioTrackUnavailable {
      // Stopped or replaced meanwhile: do not start afterwards.
      if (generation != _generation) return;
      _active = system;
      await system.play(wav);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    final active = _active;
    _active = null;
    if (active != null) await active.stop();
  }
}
