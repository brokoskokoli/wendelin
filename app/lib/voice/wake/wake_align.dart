import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

/// Result of [alignWakeTail]: [overlap] samples at the end of the service's
/// tail are the same recording as the start of the app's audio (`null`: not
/// sure, use the timestamps), [peak] is the normalized correlation 0..100 of
/// the best candidate (0 if none was tried).
typedef WakeAlign = ({int? overlap, int peak});

/// Smallest overlap that is compared (samples, 16 ms).
const wakeAlignMinOverlap = 256;

/// How far below the estimate the overlap may be (samples, 10 ms). The
/// timestamps never suggest much more than the truth.
const wakeAlignBelow = 160;

/// How far above the estimate the overlap may be (samples, 60 ms). The
/// timestamp estimate cuts systematically too little (5-30 ms), so the
/// window is asymmetric: a match elsewhere is a wrong match.
const wakeAlignAbove = 960;

/// Smallest correlation peak (percent) that is trusted.
const wakeAlignMinPeak = 88;

/// How far the best peak must stand out from the best peak elsewhere
/// (percent), so periodic signals are not trusted.
const wakeAlignMinMargin = 10;

/// A peak this high (percent) is a copy of the same recording, not a chance
/// match; it only has to beat the rivals by [wakeAlignSureMargin] (voiced
/// speech repeats itself with every pitch period at 90 % and more).
const wakeAlignSure = 97;

/// Margin (percent) that suffices for a peak of at least [wakeAlignSure].
const wakeAlignSureMargin = 3;

/// Smallest RMS (16-bit units) of both compared segments; below that the
/// signal is room noise at best.
const wakeAlignMinRms = 20;

/// Finds how many samples at the end of [tail] the start of [app] repeats
/// (WP149): both are the same microphone, the service's recording was open
/// until after the app's first frame. [estimate] is the overlap in samples
/// the timestamps suggest; only [wakeAlignBelow] below and [wakeAlignAbove]
/// above it is searched, never below [wakeAlignMinOverlap]. If the
/// timestamps see a gap ([estimate] < 0: the app continues after the tail)
/// there is no overlap to find: `null` (the caller fills the gap), since a
/// match could only be a chance one and would cut real speech.
/// Normalized cross-correlation of `tail[N-o..N)` against `app[0..o)` for
/// every `o` of that window, all at full rate (about 2M multiply-adds, up to
/// 6M: run it off the UI isolate, see [alignWakeTailOffUi]).
/// Fail-closed: rejects (overlap `null`) too little signal, a peak below
/// [wakeAlignMinPeak] and a peak that does not stand out from the best
/// rival outside its own main lobe (periodic signal).
WakeAlign alignWakeTail(
  Int16List tail,
  Int16List app, {
  required int estimate,
}) {
  if (estimate < 0) return (overlap: null, peak: 0);
  final maxO = math.min(tail.length, app.length);
  final lo = math.max(wakeAlignMinOverlap, estimate - wakeAlignBelow);
  final hi = math.min(maxO, estimate + wakeAlignAbove);
  if (hi < lo) return (overlap: null, peak: 0);
  // Energy prefix of the app and suffix of the tail (sums of squares).
  final ea = Float64List(hi + 1);
  final et = Float64List(hi + 1);
  for (var k = 0; k < hi; k++) {
    final a = app[k].toDouble();
    final t = tail[tail.length - 1 - k].toDouble();
    ea[k + 1] = ea[k] + a * a;
    et[k + 1] = et[k] + t * t;
  }
  // Every overlap in the window at full rate: a coarse pre-selection can
  // miss the true peak (and its rivals), and the window is small.
  final n = hi - lo + 1;
  final ncc = Float64List(n);
  var best = 0;
  for (var o = lo; o <= hi; o++) {
    final base = tail.length - o;
    var dot = 0;
    for (var i = 0; i < o; i++) {
      dot += tail[base + i] * app[i];
    }
    final d = math.sqrt(ea[o] * et[o]);
    final v = d > 0 ? dot / d : 0.0;
    ncc[o - lo] = v;
    if (v > ncc[best]) best = o - lo;
  }
  // Rival: best value away from the best peak's own main lobe, which ends
  // at the first rise on each side (a fixed width would hide real rivals).
  var second = 0.0;
  var l = best;
  while (l > 0 && ncc[l - 1] < ncc[l]) {
    l--;
  }
  var r = best;
  while (r < n - 1 && ncc[r + 1] < ncc[r]) {
    r++;
  }
  for (var i = 0; i < n; i++) {
    if ((i < l || i > r) && ncc[i] > second) second = ncc[i];
  }
  final bestO = best + lo;
  final peak = (ncc[best] * 100).round().clamp(0, 100);
  final margin = ((ncc[best] - second) * 100).round();
  final loud =
      _rms(tail, tail.length - bestO, bestO) >= wakeAlignMinRms &&
      _rms(app, 0, bestO) >= wakeAlignMinRms;
  final ok =
      loud &&
      peak >= wakeAlignMinPeak &&
      margin >=
          (peak >= wakeAlignSure ? wakeAlignSureMargin : wakeAlignMinMargin);
  return (overlap: ok ? bestO : null, peak: peak);
}

/// [alignWakeTail] in a short-lived isolate: the search costs up to 6M
/// multiply-adds (tens of ms on a phone), which must not stall the UI.
Future<WakeAlign> alignWakeTailOffUi(
  Int16List tail,
  Int16List app, {
  required int estimate,
}) => Isolate.run(() => alignWakeTail(tail, app, estimate: estimate));

double _rms(Int16List x, int from, int n) {
  var s = 0.0;
  for (var i = from; i < from + n; i++) {
    s += x[i].toDouble() * x[i];
  }
  return math.sqrt(s / n);
}
