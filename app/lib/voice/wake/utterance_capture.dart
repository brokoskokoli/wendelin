import 'dart:math' as math;
import 'dart:typed_data';

/// Why a recording was kept or dropped.
enum UtteranceVerdict {
  /// Usable.
  accepted,

  /// Nothing but silence or a click.
  noSpeech,

  /// Too quiet.
  tooQuiet,

  /// Speech was already running when the recording began (word cut off).
  cutOff,

  /// Too long for one word (talking, noise).
  tooLong,

  /// Set by the enroller, not by the capture (WP140): loud enough, but not
  /// „Wendelin“ (click, knock, cough, another word).
  notWord,

  /// Set by the enroller (WP140): a template that does not fit the others.
  inconsistent,

  /// Set by the enroller (WP140): the content could not be checked.
  unchecked,
}

/// Outcome of one recording.
final class Utterance {
  /// Creates an outcome.
  const Utterance(this.verdict, [this.pcm, this.speechEnd = 0]);

  /// Decision.
  final UtteranceVerdict verdict;

  /// The speech with a little lead and tail (only when accepted).
  final Int16List? pcm;

  /// Sample in [pcm] where the speech ends.
  final int speechEnd;
}

/// Cuts one spoken word out of a microphone stream by energy (WP60):
/// noise floor from the first 300 ms, speech starts above it, the word
/// ends after 450 ms of quiet. Rejects recordings that are too quiet, cut
/// off, too long or empty. Pure; the audio lives only inside the object
/// until [feed] returns the result.
final class UtteranceCapture {
  /// Creates a capture with the limits in samples at 16 kHz.
  UtteranceCapture({
    this.maxWait = 6 * 16000,
    this.maxSpeech = 2 * 16000 + 8000,
    this.minSpeech = 4000,
    this.minPeak = 0.02,
  });

  /// Longest wait for speech.
  final int maxWait;

  /// Longest speech (about 2.5 s).
  final int maxSpeech;

  /// Shortest speech (250 ms).
  final int minSpeech;

  /// Lowest peak level (RMS of a 20 ms block, 0–1) of the word.
  final double minPeak;

  static const _block = 320; // 20 ms
  static const _calibration = 15; // blocks = 300 ms
  static const _quiet = 22; // blocks = 440 ms
  static const _loud = 0.03; // RMS that is clearly speech, not noise
  static const _lead = 10; // blocks kept before the speech

  final _samples = <int>[];
  final _floors = <double>[];
  var _consumed = 0; // samples already evaluated (multiple of _block)
  var _floor = 0.0;
  var _first = -1; // block index of the first speech block
  var _last = -1;
  var _peak = 0.0;
  Utterance? _done;

  /// Level (0–1, RMS) of the latest 20 ms block.
  double level = 0;

  /// Feeds [frame]; returns the result once the word is complete (or
  /// rejected), `null` while the recording goes on.
  Utterance? feed(Int16List frame) {
    if (_done != null) return _done;
    _samples.addAll(frame);
    while (_samples.length - _consumed >= _block) {
      final r = _evaluate(_consumed ~/ _block);
      _consumed += _block;
      if (r != null) return _done = r;
    }
    return null;
  }

  double _rms(int from) {
    var sum = 0.0;
    for (var i = from; i < from + _block; i++) {
      sum += _samples[i] * _samples[i];
    }
    return math.sqrt(sum / _block) / 32768;
  }

  Utterance? _evaluate(int block) {
    final rms = _rms(block * _block);
    level = rms;
    if (block < _calibration) {
      _floors.add(rms);
      if (block == _calibration - 1) {
        final sorted = [..._floors]..sort();
        _floor = sorted[sorted.length ~/ 2];
        // Speech from the very first blocks on: the word is cut off.
        if (_floors[0] > _loud && _floors[1] > _loud) {
          return const Utterance(UtteranceVerdict.cutOff);
        }
      }
      return null;
    }
    final speech = rms > math.max(_floor * 4, 0.006);
    if (speech) {
      if (_first < 0) _first = block;
      _last = block;
      if (rms > _peak) _peak = rms;
      if ((block - _first + 1) * _block > maxSpeech) {
        return const Utterance(UtteranceVerdict.tooLong);
      }
      return null;
    }
    if (_first < 0) {
      return (block + 1) * _block > maxWait
          ? const Utterance(UtteranceVerdict.noSpeech)
          : null;
    }
    if (block - _last < _quiet) return null;
    return _finish();
  }

  Utterance _finish() {
    final length = (_last - _first + 1) * _block;
    if (length < minSpeech) return const Utterance(UtteranceVerdict.noSpeech);
    if (_peak < minPeak) return const Utterance(UtteranceVerdict.tooQuiet);
    final from = math.max(0, (_first - _lead) * _block);
    final to = math.min(_samples.length, (_last + 1 + 8) * _block);
    return Utterance(
      UtteranceVerdict.accepted,
      Int16List.fromList(_samples.sublist(from, to)),
      (_last + 1) * _block - from,
    );
  }
}
