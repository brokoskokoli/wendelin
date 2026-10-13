import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

/// [AudioInput] that passes frames through unchanged and reports the level
/// of each frame (0–1) on [levels], for the waveform in the overlay and on
/// the main screen.
final class MeteredAudioInput implements AudioInput {
  /// Wraps [inner].
  MeteredAudioInput(this.inner);

  /// The real microphone.
  final AudioInput inner;

  final _levels = StreamController<double>.broadcast(sync: true);

  /// Level per frame (RMS relative to full scale, with a square-root curve
  /// so quiet speech is still visible).
  Stream<double> get levels => _levels.stream;

  @override
  bool get isRunning => inner.isRunning;

  @override
  Stream<Int16List> start() => inner.start().map((frame) {
    if (!_levels.isClosed) _levels.add(levelOf(frame));
    return frame;
  });

  @override
  Future<void> stop() async {
    await inner.stop();
    if (!_levels.isClosed) _levels.add(0);
  }

  /// Closes [levels].
  Future<void> dispose() => _levels.close();

  /// Level of [frame]: RMS / 32768, square-rooted, clamped to 0–1.
  static double levelOf(Int16List frame) {
    if (frame.isEmpty) return 0;
    var sum = 0.0;
    for (final s in frame) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / frame.length) / 32768;
    return math.sqrt(rms).clamp(0.0, 1.0);
  }
}
