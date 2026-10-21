import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../../voice/voice_log.dart';
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
  ///
  /// WP118: while [communication] is true (the answer runs in the call path)
  /// the player uses `USAGE_VOICE_COMMUNICATION`.
  AudioplayersPlayback([AudioPlayer? player, this.communication])
    : _given = player;

  /// Whether the answer plays in the call path right now (read per [play]).
  final bool Function()? communication;

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

  /// The same with the usage of a call (WP118, K88): the echo canceller of
  /// the call path then knows this playback.
  ///
  /// `audioMode` must be `inCommunication`: audioplayers_android sets
  /// `audioManager.mode = context.audioMode` at every play
  /// (`WrappedPlayer.kt:171`, default `MODE_NORMAL`) and would otherwise undo
  /// the call mode of `SpeechRoute`.
  static final AudioContext communicationContext = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.speech,
      usageType: AndroidUsageType.voiceCommunication,
      audioMode: AndroidAudioMode.inCommunication,
      audioFocus: AndroidAudioFocus.gainTransientMayDuck,
    ),
  );
  bool? _contextComm;
  Completer<void>? _done;
  StreamSubscription<void>? _complete;

  @override
  Future<void> play(Wav wav) async {
    await stop();
    final done = _done = Completer<void>();
    _complete ??= _player.onPlayerComplete.listen((_) => _finish());
    try {
      final comm = communication?.call() ?? false;
      if (_contextComm != comm) {
        await _player.setAudioContext(comm ? communicationContext : context);
        _contextComm = comm;
        voiceLog('speech-route', {
          'usage': comm ? 'voice_communication' : 'assistant',
        });
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
