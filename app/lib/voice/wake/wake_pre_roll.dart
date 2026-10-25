import 'dart:async';
import 'dart:typed_data';

import 'package:wendelin_voice/wendelin_voice.dart';

import '../../di/wake_settings.dart';
import '../../platform/assistant_platform.dart';
import '../voice_controller.dart';
import '../voice_log.dart';

/// Takes the audio of the wake word hit from the service and, if [tone] is
/// set, plays the tone (WP68); shared by the overlay and the chat (WP93).
/// The tone follows the take: the service no longer records, the new
/// microphone silences the first [wakeToneMuteSamples] samples. Without a
/// tone (setting) or if the speaker is evidently continuing already,
/// nothing is played and nothing silenced. `null` if nobody left a hit.
Future<WakePreRoll?> takeWakePreRoll({
  required AssistantPlatform platform,
  required bool tone,
  required Future<void> Function() playTone,
}) async {
  // The service records on until the new microphone has its first frame
  // (WP146); `finish` ends that, once.
  final taken = await platform.takeWakeHandoff(keepOpen: true);
  if (taken == null) return null;
  Future<WakeTail?>? finished;
  Future<WakeTail?> finish() => finished ??= platform.finishWakeHandoff().then(
    (t) => t == null ? null : (pcm: t.pcm, lastSampleAtMs: t.lastSampleAtMs),
  );
  final pcm = taken.pcm;
  final continues = speechAfterWakeWord(pcm, taken.wakeEnd);
  voiceLog('wake-handoff', {
    'ms': samplesToDuration(pcm.length),
    'captured': Duration(milliseconds: taken.capturedMs),
    'continues': continues,
  });
  final play = tone && !continues;
  if (play) unawaited(playTone());
  return WakePreRoll(
    pcm: pcm,
    wakeEnd: taken.wakeEnd,
    muteMicSamples: play ? wakeToneMuteSamples : 0,
    lastSampleAtMs: taken.lastSampleAtMs,
    finish: finish,
  );
}

/// The longest hole that is filled with silence; a larger one is not a
/// handover hole (WP146).
const wakeHoleMax = Duration(milliseconds: 1500);

/// Joins [pre] and what the service recorded afterwards ([tail]) to the first
/// frame of the new microphone (WP146):
///
/// - the tail starts at the take, where the confirmation tone starts too: its
///   first [WakePreRoll.muteMicSamples] samples are silenced (the service
///   would record the tone), and the new microphone mutes only the rest;
/// - the service recorded on until after that first frame: the doubled end of
///   the tail is cut (negative gap), no word comes twice;
/// - a hole that remains (positive gap) is inserted as silence (at most
///   [wakeHoleMax]), so words are not glued together.
///
/// Logs `wake-gap` (signed gap in ms, `tail`, `trim`, `silence`; numbers only).
WakePreRoll bridgeWakeTail(
  WakePreRoll pre,
  WakeTail tail, {
  int? firstFrameAtMs,
  int? firstFrameSamples,
  int? afterTakeMs,
}) {
  var audio = Int16List.fromList(tail.pcm);
  final muted = pre.muteMicSamples < audio.length
      ? pre.muteMicSamples
      : audio.length;
  audio.fillRange(0, muted, 0);
  final last = tail.lastSampleAtMs;
  int? gap;
  if (last != null && last > 0 && firstFrameAtMs != null) {
    gap = wakeGapMs(
      firstFrameAtMs: firstFrameAtMs,
      frameSamples: firstFrameSamples ?? 0,
      lastSampleAtMs: last,
    );
  }
  var trim = 0;
  var silence = 0;
  if (gap != null && gap < 0) {
    trim = (-gap * 16).clamp(0, audio.length).toInt();
    audio = Int16List.sublistView(audio, 0, audio.length - trim);
  } else if (gap != null && gap > 0) {
    silence = durationToSamples(Duration(milliseconds: gap));
    final max = durationToSamples(wakeHoleMax);
    if (silence > max) silence = max;
  }
  final out = Int16List(pre.pcm.length + audio.length + silence)
    ..setAll(0, pre.pcm)
    ..setAll(pre.pcm.length, audio);
  final added = audio.length + silence;
  voiceLog('wake-gap', {
    'ms': ?gap,
    'afterTake': ?afterTakeMs,
    'mode': 'overlap',
    'tail': samplesToDuration(tail.pcm.length),
    'trim': samplesToDuration(trim),
    'silence': samplesToDuration(silence),
  });
  return pre.withAudio(
    out,
    muteMicSamples: pre.muteMicSamples > added ? pre.muteMicSamples - added : 0,
    lastSampleAtMs: null,
  );
}
