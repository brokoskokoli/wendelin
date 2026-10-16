import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

/// Level gate for short keywords („Stopp“, WP80): tells whether the last
/// moments held speech-level sound compared with the quiet background of the
/// same stream. A keyword hit that arrives while the microphone only
/// delivers silence (AEC output, closed room) is no hit.
///
/// The gate keeps the root mean square of 20 ms blocks. The background is
/// the noise floor: it follows quiet blocks fast and loud ones slowly (about
/// ten seconds), so a steady echo raises it and only a clear rise over it
/// counts as speech.
final class SpeechGate {
  /// Creates the gate. [minRms] is the absolute level (16-bit samples) the
  /// recent peak must reach, [ratio] the factor over the noise floor,
  /// [memory] how far back the peak is looked for.
  SpeechGate({
    this.minRms = 150,
    this.ratio = 4,
    this.memory = const Duration(milliseconds: 800),
  }) : _maxBlocks = math.max(1, memory.inMilliseconds ~/ _blockMs);

  /// Smallest level of speech (RMS of a 20 ms block).
  final double minRms;

  /// Required factor over the noise floor.
  final double ratio;

  /// Look-back of the peak.
  final Duration memory;

  static const _blockMs = 20;
  static const _block = 16000 * _blockMs ~/ 1000;
  final int _maxBlocks;
  final _recent = ListQueue<double>();
  double _floor = -1;

  /// Noise floor (RMS), `0` before the first audio.
  double get floor => _floor < 0 ? 0 : _floor;

  /// Peak block level of the look-back (RMS).
  double get peak => _recent.isEmpty ? 0 : _recent.reduce(math.max);

  /// Whether the look-back holds speech-level sound.
  bool get active => peak >= math.max(minRms, floor * ratio);

  /// Feeds [frame] (16 kHz mono).
  void feed(Int16List frame) {
    for (var i = 0; i < frame.length; i += _block) {
      final end = math.min(i + _block, frame.length);
      var sum = 0.0;
      for (var j = i; j < end; j++) {
        sum += frame[j] * frame[j];
      }
      final rms = math.sqrt(sum / (end - i));
      _recent.addLast(rms);
      if (_recent.length > _maxBlocks) _recent.removeFirst();
      if (_floor < 0) {
        _floor = rms;
      } else {
        _floor += (rms - _floor) * (rms < _floor ? 0.2 : 0.002);
      }
    }
  }

  /// Forgets everything (new stream).
  void reset() {
    _recent.clear();
    _floor = -1;
  }
}
