import 'dart:typed_data';

import '../io/audio_input.dart';

/// End (sample index) of the last 20 ms block of [pcm] whose level reaches
/// [minLevel]; 0 if there is none.
int speechEnd(Int16List pcm, num minLevel) {
  const block = 320;
  var last = 0;
  for (var i = 0; i < pcm.length; i += block) {
    final end = i + block < pcm.length ? i + block : pcm.length;
    var sum = 0.0;
    for (var j = i; j < end; j++) {
      sum += pcm[j] * pcm[j];
    }
    if (sum / (end - i) >= minLevel * minLevel) last = end;
  }
  return last;
}

/// The last [clip] of [all] (the ring, [fed] samples seen so far), ending
/// shortly after the last loud sample [lastLoud] instead of at "now": a late
/// stage 1 hit (the check starts after [settle]) must not push the word out
/// of the clip (device finding 2026-10-22). Speech up to now: the clip ends
/// now. Trailing silence = settle: Whisper needs quiet after a short word to
/// recognise it; the end stays min(now, lastLoud + settle).
Int16List clipEndingAtSpeech(
  Int16List all, {
  required int fed,
  required int lastLoud,
  required Duration settle,
  required Duration clip,
}) {
  var end = all.length;
  final atSpeech = lastLoud + durationToSamples(settle) - (fed - all.length);
  if (atSpeech < end) end = atSpeech;
  if (end <= 0) return all; // loud block left the ring: quiet, skipped
  final n = durationToSamples(clip);
  return Int16List.sublistView(all, end > n ? end - n : 0, end);
}
