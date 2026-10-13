import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'pcm.dart';
import 'sherpa_tts.dart';

/// [AudioPlayback] with `audioplayers` (Android `MediaPlayer`, no GMS):
/// plays the WAV from memory and completes when it ended or was stopped.
final class AudioplayersPlayback implements AudioPlayback {
  /// Creates the playback; [player] is created lazily.
  AudioplayersPlayback([AudioPlayer? player]) : _given = player;

  final AudioPlayer? _given;
  late final AudioPlayer _player = _given ?? AudioPlayer();
  Completer<void>? _done;
  StreamSubscription<void>? _complete;

  @override
  Future<void> play(Wav wav) async {
    await stop();
    final done = _done = Completer<void>();
    _complete ??= _player.onPlayerComplete.listen((_) => _finish());
    try {
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
