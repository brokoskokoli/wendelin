import 'dart:typed_data';

/// Whether the audio after the wake word ([wakeEnd] samples into [pcm], a
/// short margin skipped) already holds speech: at least [minWindows]
/// consecutive 30 ms windows with a mean absolute amplitude of [loudness]
/// (WP68). A cheap energy check, no VAD: it only decides whether the
/// confirmation tone is skipped because the user is already talking.
bool speechAfterWakeWord(
  Int16List pcm,
  int? wakeEnd, {
  int loudness = 900,
  int minWindows = 4,
  int margin = 1600,
}) {
  const window = 480;
  final from = (wakeEnd ?? pcm.length) + margin;
  var run = 0;
  for (var i = from; i + window <= pcm.length; i += window) {
    var sum = 0;
    for (var j = i; j < i + window; j++) {
      sum += pcm[j].abs();
    }
    run = sum ~/ window >= loudness ? run + 1 : 0;
    if (run >= minWindows) return true;
  }
  return false;
}
