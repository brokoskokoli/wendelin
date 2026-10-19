import 'dart:async';

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
  final taken = await platform.takeWakeHandoff();
  if (taken == null) return null;
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
  );
}
