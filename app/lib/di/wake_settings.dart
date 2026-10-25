import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/voice/audio_playback.dart';
import '../platform/voice/pcm.dart';
import '../platform/wake/wake_platform.dart';
import 'core_providers.dart';
import 'dispose_tracker.dart';

// Settings of the wake word page that only the app needs (WP50 part b);
// switch and condition live in `wake_service.dart`.

/// Setting „Bestätigungston“ (default on): a short tone at a hit.
final wakeToneKey = SettingKey.boolean('wake.tone', defaultValue: true);

/// Whether the explanation before the first switch-on was confirmed.
final wakeExplainedKey = SettingKey.boolean(
  'wake.explained',
  defaultValue: false,
);

/// The confirmation tone on or off.
final wakeToneProvider = AsyncNotifierProvider<WakeToneNotifier, bool>(
  WakeToneNotifier.new,
);

/// See [wakeToneProvider].
final class WakeToneNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async =>
      await ref.read(storageProvider).settings.get(wakeToneKey) ?? true;

  /// Switches the tone.
  Future<void> set({required bool enabled}) async {
    state = AsyncData(enabled);
    await ref.read(storageProvider).settings.set(wakeToneKey, enabled);
  }
}

/// State of the service right now (re-read on resume and after changes).
final wakeStatusProvider = FutureProvider.autoDispose<WakeServiceStatus>(
  (ref) => ref.watch(wakePlatformProvider).status(),
);

/// Length of the confirmation tone in samples (0.15 s at 16 kHz).
const wakeToneSamples = 2400;

/// Microphone samples set to zero after a tone starts: the tone plus 50 ms
/// (the speaker is not cancelled from the recording otherwise).
const wakeToneMuteSamples = wakeToneSamples + 800;

/// Short tone (660 Hz, 0.15 s) at a wake word hit (replaced in tests).
final wakeConfirmToneProvider = Provider<Future<void> Function()>((ref) {
  final playback = AudioplayersPlayback();
  onDisposeTracked(ref, playback.dispose);
  final samples = Int16List(wakeToneSamples);
  for (var i = 0; i < samples.length; i++) {
    final fade = math.min(1.0, math.min(i, samples.length - i) / 400);
    samples[i] = (math.sin(2 * math.pi * 660 * i / 16000) * 7000 * fade)
        .round();
  }
  return () => playback.play(Wav(samples));
});
