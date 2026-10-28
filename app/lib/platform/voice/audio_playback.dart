import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'pcm.dart';
import 'sherpa_tts.dart';

/// [AudioPlayback] with `audioplayers` (Android `MediaPlayer`, no GMS):
/// plays the WAV from memory and completes when it ended or was stopped.
///
/// The player asks only for a transient focus that lets other players
/// continue at lower volume (`gainTransientMayDuck`, WP90); an answer
/// spoken by this engine holds the same focus for its whole length anyway
/// (`DuckingTextToSpeech`).
final class AudioplayersPlayback implements AudioPlayback {
  /// Creates the playback; [player] is created lazily.
  AudioplayersPlayback([AudioPlayer? player]) : _given = player;

  final AudioPlayer? _given;
  late final AudioPlayer _player = _given ?? AudioPlayer();

  /// The audio context of the speech output: speech of an assistant that
  /// only ducks other players.
  static final AudioContext context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.assistant,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );

  bool _contextSet = false;
  Completer<void>? _done;
  StreamSubscription<void>? _complete;

  @override
  Future<void> play(Wav wav) async {
    // The new play is set before the old one is stopped, so a stop during that
    // wait reaches this play (and it must not start afterwards).
    final previous = _done;
    final done = _done = Completer<void>();
    if (previous != null) {
      if (!previous.isCompleted) previous.complete();
      await _player.stop();
      if (!identical(_done, done)) return;
    }
    _complete ??= _player.onPlayerComplete.listen((_) => _finish());
    try {
      // A stop (or a newer play) during the awaits ends this play: the
      // player must not start afterwards, and a second stop would do nothing.
      if (!_contextSet) {
        await _player.setAudioContext(context);
        _contextSet = true;
        if (!identical(_done, done)) return;
      }
      await _player.play(BytesSource(wav.encode(), mimeType: 'audio/wav'));
    } on Object {
      _finish();
      rethrow;
    }
    // Safety limit: playback never takes much longer than the audio.
    await done.future.timeout(
      wav.duration + const Duration(seconds: 5),
      onTimeout: () {},
    );
    if (identical(_done, done)) _done = null;
  }

  void _finish() {
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> stop() async {
    if (_done == null) return;
    _finish();
    await _player.stop();
  }

  /// Stops and releases the player.
  Future<void> dispose() async {
    await stop();
    await _complete?.cancel();
    _complete = null;
    await _player.dispose();
  }
}
