import 'dart:math' as math;
import 'dart:typed_data';

import '../io/speech_to_text.dart';

/// Longest PCM (16 kHz) that goes to the recognizer in one call (WP192).
///
/// Whisper has a 30 s window and discards everything after it (sherpa-onnx:
/// „Only waves less than 30 seconds are supported …“), so a long hold
/// recording is cut below that, with headroom for the model's own padding.
const sttSegmentLimitSamples = 25 * 16000;

/// How far before the limit the quietest spot is searched (5 s).
const _searchSamples = 5 * 16000;

/// RMS window (20 ms at 16 kHz).
const _window = 320;

/// Splits [pcm] into pieces of at most [limit] samples, each cut at the
/// quietest [_window] (lowest RMS; on a tie the latest) within the last
/// 5 s before the limit, so words are rarely cut through.
///
/// A [pcm] of at most [limit] samples comes back as one piece (the same
/// list, not a copy). The pieces are consecutive views: concatenated they
/// are exactly [pcm] (no sample lost or doubled).
List<Int16List> splitAtQuietPoints(
  Int16List pcm, {
  int limit = sttSegmentLimitSamples,
}) {
  if (pcm.length <= limit) return [pcm];
  final search = math.min(_searchSamples, limit - _window);
  final out = <Int16List>[];
  var start = 0;
  while (pcm.length - start > limit) {
    final cut = _quietestCut(pcm, start + limit - search, start + limit);
    out.add(Int16List.sublistView(pcm, start, cut));
    start = cut;
  }
  out.add(Int16List.sublistView(pcm, start));
  return out;
}

/// Center of the quietest window that starts in [from]..[to] - window.
int _quietestCut(Int16List pcm, int from, int to) {
  var bestStart = to - _window;
  var best = double.infinity;
  for (var s = to - _window; s >= from; s -= _window ~/ 2) {
    var sum = 0.0;
    for (var i = s; i < s + _window; i++) {
      sum += pcm[i] * pcm[i];
    }
    if (sum < best) {
      best = sum;
      bestStart = s;
    }
  }
  return bestStart + _window ~/ 2;
}

/// Joins the transcripts of consecutive segments into one: texts with a
/// space (empty ones skipped), the minimum confidence (`null` only if no
/// segment has one), the language of the first segment that has one.
Transcript mergeTranscripts(List<Transcript> parts) {
  final confidences = [
    for (final p in parts)
      if (p.confidence != null) p.confidence!,
  ];
  return Transcript(
    text: [
      for (final p in parts)
        if (p.text.trim().isNotEmpty) p.text.trim(),
    ].join(' '),
    language: parts.map((p) => p.language).nonNulls.firstOrNull,
    confidence: confidences.isEmpty ? null : confidences.reduce(math.min),
  );
}
