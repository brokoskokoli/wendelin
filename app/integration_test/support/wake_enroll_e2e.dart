import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/platform/voice/wav_audio_input.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_enroller.dart';
import 'package:wendelin_voice/wendelin_voice.dart' show WakeTemplateStore;

import 'enroll_log.dart';
export 'enroll_log.dart' show enrollLogProblem;

// Shared enrollment of the wake device tests (WP151). Since WP142 the
// enrollment accepts only „Hey Wendelin“ vouched for by the recognizer or the
// classifier (>= 0,98), so the recordings are `AnnaHey_01..15.wav` (synthetic
// voice Anna, „Hey Wendelin“); `Anna_*.wav` („Wendelin“ alone) are rejected
// as missing „Hey“ or unchecked. The prompts and probes of the tests are
// other files (`test-solo.wav` …), so the templates and the probe never
// share a clip.

/// Number of recordings the enrollment asks for (as the screen).
const annaHeyCount = 15;

/// The 15 enrollment recordings `AnnaHey_01..15.wav` in [wavs]: exactly as
/// many as the target. A good recording that is rejected or dropped as an
/// outlier makes the sequence repeat its last file and still reach the
/// target, so `accepted` alone proves nothing: [enrollAnnaDirect] checks
/// `rejected == 0` and the UI tests [enrollLogProblem] on the voice log.
List<Int16List> annaHeyClips(String wavs) => [
  for (var i = 1; i <= annaHeyCount; i++)
    WavAudioInput.file('$wavs/AnnaHey_${i.toString().padLeft(2, '0')}.wav')
        .samples,
];

/// Enrolls Anna without the screen, as the app does: the enrollment feature
/// chain (classifier if installed) and the configured recognizer
/// ([wakeEnrollVerifierProvider], so `voiceSettingsKey` needs an
/// `sttModel`) as content check, target [annaHeyCount]. Stores into [store]
/// and returns the enroller. Fails if not every recording was accepted.
Future<WakeEnroller> enrollAnnaDirect(
  ProviderContainer c,
  WakeTemplateStore store,
  String wavs,
) async {
  final makeFeatures = await c.read(wakeEnrollFeaturesFactoryProvider.future);
  final verifier = await c.read(wakeEnrollVerifierProvider.future);
  final enroller = WakeEnroller(
    audio: WavAudioInput.sequence(annaHeyClips(wavs), speed: 4),
    features: makeFeatures(),
    store: store,
    speakerId: 'anna',
    pause: Duration.zero,
    verifier: verifier,
  );
  await enroller.run();
  expect(enroller.error, isNull);
  expect(
    enroller.accepted,
    annaHeyCount,
    reason: 'rejected ${enroller.rejected}, last ${enroller.lastVerdict}',
  );
  expect(
    enroller.rejected,
    0,
    reason: 'a rejected or outlier recording was replaced by the last file',
  );
  await enroller.finish();
  return enroller;
}

/// Collects the voice-log lines of this process (and still prints them, so
/// logcat keeps them). Call before the enrollment, check afterwards with
/// [enrollLogProblem].
List<String> captureVoiceLog() {
  final lines = <String>[];
  voiceLogSink = (l) {
    lines.add(l);
    debugPrint(l);
  };
  return lines;
}
