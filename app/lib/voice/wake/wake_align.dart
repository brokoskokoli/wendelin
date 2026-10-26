import 'dart:math' as math;
import 'dart:typed_data';

/// Result of [alignWakeTail]: [overlap] samples at the end of the service's
/// tail are the same recording as the start of the app's audio (`null`: not
/// sure, use the timestamps), [peak] is the normalized correlation 0..100 of
/// the best candidate (0 if none was tried).
typedef WakeAlign = ({int? overlap, int peak});

/// Smallest overlap that is compared (samples, 16 ms).
const wakeAlignMinOverlap = 256;

/// Search window around the estimate (samples, 150 ms).
const wakeAlignSearch = 2400;

/// Smallest correlation peak (percent) that is trusted.
const wakeAlignMinPeak = 80;

/// How far the best peak must stand out from the best peak elsewhere
/// (percent), so periodic signals are not trusted.
const wakeAlignMinMargin = 10;

/// Smallest RMS (16-bit units) of both compared segments; below that the
/// signal is room noise at best.
const wakeAlignMinRms = 20;

const _dec = 4;
// Peaks closer than this (decimated blocks, ~1 ms) belong to the best one.
const _skip = 4;

/// Finds how many samples at the end of [tail] the start of [app] repeats
/// (WP149): both are the same microphone, the service's recording was open
/// until after the app's first frame. [estimate] is the overlap in samples
/// the timestamps suggest (may be zero or negative); only
/// [wakeAlignSearch] around it is searched. Normalized cross-correlation of
/// `tail[N-o..N)` against `app[0..o)` for every `o`, on a 4x decimated copy,
/// then refined at full rate. Rejects (overlap `null`) too little signal, a
/// peak below [wakeAlignMinPeak] and a peak that is not unique (periodic
/// signal). About 1M multiply-adds for the usual window.
WakeAlign alignWakeTail(
  Int16List tail,
  Int16List app, {
  required int estimate,
}) {
  final maxO = math.min(tail.length, app.length);
  final lo = math.max(wakeAlignMinOverlap, estimate - wakeAlignSearch);
  final hi = math.min(maxO, estimate + wakeAlignSearch);
  if (hi < lo) return (overlap: null, peak: 0);
  final kt = hi ~/ _dec;
  final lod = (lo + _dec - 1) ~/ _dec;
  if (kt < lod) return (overlap: null, peak: 0);
  // Tail blocks end at the tail's end; app blocks start at its start.
  final td = Float64List(kt);
  final ad = Float64List(kt);
  for (var k = 0; k < kt; k++) {
    var st = 0;
    var sa = 0;
    final tb = tail.length - _dec * (kt - k);
    final ab = _dec * k;
    for (var j = 0; j < _dec; j++) {
      st += tail[tb + j];
      sa += app[ab + j];
    }
    td[k] = st / _dec;
    ad[k] = sa / _dec;
  }
  // Energy prefix of the app, suffix of the tail.
  final ea = Float64List(kt + 1);
  final et = Float64List(kt + 1);
  for (var k = 0; k < kt; k++) {
    ea[k + 1] = ea[k] + ad[k] * ad[k];
    et[k + 1] = et[k] + td[kt - 1 - k] * td[kt - 1 - k];
  }
  final n = kt - lod + 1;
  final ncc = Float64List(n);
  var best = -1;
  for (var od = lod; od <= kt; od++) {
    final off = kt - od;
    var dot = 0.0;
    for (var i = 0; i < od; i++) {
      dot += td[off + i] * ad[i];
    }
    final d = math.sqrt(ea[od] * et[od]);
    final v = d > 0 ? dot / d : 0.0;
    ncc[od - lod] = v;
    if (best < 0 || v > ncc[best]) best = od - lod;
  }
  // Second best, away from the best.
  var second = -1.0;
  for (var i = 0; i < n; i++) {
    if ((i - best).abs() > _skip && ncc[i] > second) second = ncc[i];
  }
  if (second < 0) second = 0;
  // Refine at full rate.
  final center = (best + lod) * _dec;
  var bestO = -1;
  var bestV = -2.0;
  for (var o = center - 2 * _dec; o <= center + 2 * _dec; o++) {
    if (o < wakeAlignMinOverlap || o > maxO) continue;
    final v = _ncc(tail, app, o);
    if (v > bestV) {
      bestV = v;
      bestO = o;
    }
  }
  if (bestO < 0) return (overlap: null, peak: 0);
  final peak = (bestV * 100).round().clamp(0, 100);
  final margin = ((bestV - second) * 100).round();
  final loud =
      _rms(tail, tail.length - bestO, bestO) >= wakeAlignMinRms &&
      _rms(app, 0, bestO) >= wakeAlignMinRms;
  final ok = loud && peak >= wakeAlignMinPeak && margin >= wakeAlignMinMargin;
  return (overlap: ok ? bestO : null, peak: peak);
}

double _ncc(Int16List tail, Int16List app, int o) {
  final base = tail.length - o;
  var dot = 0.0;
  var et = 0.0;
  var ea = 0.0;
  for (var i = 0; i < o; i++) {
    final t = tail[base + i].toDouble();
    final a = app[i].toDouble();
    dot += t * a;
    et += t * t;
    ea += a * a;
  }
  final d = math.sqrt(et * ea);
  return d > 0 ? dot / d : 0;
}

double _rms(Int16List x, int from, int n) {
  var s = 0.0;
  for (var i = from; i < from + n; i++) {
    s += x[i].toDouble() * x[i];
  }
  return math.sqrt(s / n);
}
