import 'dart:async';

import 'package:flutter/services.dart';

import '../channels.dart';
import 'pcm.dart';
import 'sherpa_tts.dart';

/// The native output cannot play (no channel in this engine, or the track
/// could not be created): the caller plays on the system route instead.
final class AudioTrackUnavailable implements Exception {
  /// Creates the exception.
  const AudioTrackUnavailable(this.reason);

  /// Why (no device or address in it).
  final String reason;

  @override
  String toString() => 'AudioTrackUnavailable($reason)';
}

/// [AudioPlayback] over the native `AudioTrack` (WP188): speech of an
/// assistant on the output the user chose (the native side reads the choice
/// and follows devices coming and going). Completes when the playback head
/// reached the end or [stop] / a newer [play] ended it.
final class AudioTrackPlayback implements AudioPlayback {
  /// Creates the playback; [channel] is injectable for tests.
  AudioTrackPlayback([
    this._channel = const MethodChannel(audioPlaybackChannelName),
  ]);

  final MethodChannel _channel;
  Completer<void>? _done;

  @override
  Future<void> play(Wav wav) async {
    // The new play replaces the old one (native side as well).
    final previous = _done;
    final done = _done = Completer<void>();
    if (previous != null && !previous.isCompleted) previous.complete();
    Object? failure;
    final call = _channel
        .invokeMethod<void>('play', {
          'pcm': Uint8List.sublistView(wav.samples),
          'sampleRate': wav.sampleRate,
        })
        .then<void>((_) {}, onError: (Object e) => failure = e);
    var timedOut = false;
    // Safety limit: playback never takes much longer than the audio.
    await Future.any([done.future, call]).timeout(
      wav.duration + const Duration(seconds: 5),
      onTimeout: () => timedOut = true,
    );
    final mine = identical(_done, done);
    if (mine) _done = null;
    if (!done.isCompleted) done.complete();
    if (timedOut && mine) await _stopNative();
    final error = failure;
    if (error is MissingPluginException || error is PlatformException) {
      throw AudioTrackUnavailable('$error');
    }
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    final done = _done;
    if (done == null) return;
    _done = null;
    if (!done.isCompleted) done.complete();
    await _stopNative();
  }

  Future<void> _stopNative() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing left to stop.
    } on MissingPluginException {
      // No native side.
    }
  }

  /// Stops a running playback.
  Future<void> dispose() => stop();
}
