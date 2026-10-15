import 'dart:typed_data';

const _window = 480;

int _level(Int16List pcm, int from) {
  var sum = 0;
  for (var j = from; j < from + _window; j++) {
    sum += pcm[j].abs();
  }
  return sum ~/ _window;
}

/// Mean absolute amplitude of the quiet part of [pcm] before [end] (20th
/// percentile of the 30 ms windows): the noise of the room (WP68).
int noiseFloor(Int16List pcm, int end) {
  final levels = <int>[
    for (
      var i = 0;
      i + _window <= end && i + _window <= pcm.length;
      i += _window
    )
      _level(pcm, i),
  ]..sort();
  return levels.isEmpty ? 0 : levels[levels.length ~/ 5];
}

/// Whether the audio after the wake word ([wakeEnd] samples into [pcm], a
/// short margin skipped) already holds speech: at least [minWindows]
/// consecutive 30 ms windows whose mean absolute amplitude exceeds
/// [factor] times the noise floor before the wake word, but at least
/// [minLoudness] and at most [maxLoudness] (WP68). A cheap energy check, no
/// VAD: it only decides whether the confirmation tone is skipped because
/// the user is already talking. Quiet speech in a quiet room counts, a
/// noisy room needs louder speech.
bool speechAfterWakeWord(
  Int16List pcm,
  int? wakeEnd, {
  double factor = 3,
  int minLoudness = 250,
  int maxLoudness = 2500,
  int minWindows = 4,
  int margin = 1600,
}) {
  final end = wakeEnd ?? pcm.length;
  final loudness = (noiseFloor(pcm, end) * factor).round().clamp(
    minLoudness,
    maxLoudness,
  );
  var run = 0;
  for (var i = end + margin; i + _window <= pcm.length; i += _window) {
    run = _level(pcm, i) >= loudness ? run + 1 : 0;
    if (run >= minWindows) return true;
  }
  return false;
}
