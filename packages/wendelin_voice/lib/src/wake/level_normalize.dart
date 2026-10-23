import 'dart:math' as math;
import 'dart:typed_data';

/// Scales [pcm] (16-bit mono) so that its peak is [target] of full scale
/// (WP129; the same level the stage 2 tuning of WP133 uses). Returns a new
/// list, [pcm] stays as it is (it belongs to the pre-roll).
///
/// A clip whose peak is below [minPeak] (digital silence, a closed room) is
/// returned unchanged: scaling it up would turn noise into "speech".
Int16List normalizePeak(
  Int16List pcm, {
  double target = 0.5,
  int minPeak = 164,
}) {
  var peak = 0;
  for (final s in pcm) {
    final a = s < 0 ? -s : s;
    if (a > peak) peak = a;
  }
  if (peak < minPeak) return pcm;
  final gain = target * 32768 / peak;
  final out = Int16List(pcm.length);
  for (var i = 0; i < pcm.length; i++) {
    out[i] = math.max(-32768, math.min(32767, (pcm[i] * gain).round()));
  }
  return out;
}
