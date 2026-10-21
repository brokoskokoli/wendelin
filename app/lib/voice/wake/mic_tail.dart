import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

/// WP123: the last seconds of microphone audio of the voice pipeline (the
/// user's command), kept so the barge-in feature chain does not start cold
/// when the answer begins (it needs ~2 s of audio before its first window).
///
/// Only the pipeline's own capture goes in, never the barge-in listening
/// itself: no echo of the spoken answer in the lead-in.
final class MicTail {
  /// Keeps the last [length] (at most 5 s).
  MicTail({Duration length = const Duration(milliseconds: 2400)})
    : _ring = PreRollBuffer(capacity: length);

  final PreRollBuffer _ring;

  /// Appends [frame].
  void add(Int16List frame) => _ring.add(frame);

  /// The audio so far, oldest first.
  Int16List snapshot() => _ring.snapshot();

  /// The audio so far, and forgets it: the lead-in is used once, so no
  /// speech stays in memory longer than needed.
  Int16List take() {
    final out = _ring.snapshot();
    _ring.clear();
    return out;
  }

  /// Forgets everything.
  void clear() => _ring.clear();
}

/// [AudioInput] that copies every frame of [inner] into [tail].
final class TappedAudioInput implements AudioInput {
  /// Wraps [inner].
  TappedAudioInput(this.inner, this.tail);

  /// The real microphone.
  final AudioInput inner;

  /// Receives the frames.
  final MicTail tail;

  @override
  bool get isRunning => inner.isRunning;

  @override
  Stream<Int16List> start() {
    // A new capture: the lead-in of the one before is stale.
    tail.clear();
    return inner.start().map((f) {
      tail.add(f);
      return f;
    });
  }

  @override
  Future<void> stop() => inner.stop();
}
