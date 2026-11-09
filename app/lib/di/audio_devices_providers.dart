import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/voice/audio_devices.dart';
import '../platform/voice/audio_playback.dart';
import '../platform/voice/audio_track_playback.dart';
import '../platform/voice/routed_playback.dart';
import '../platform/voice/sherpa_tts.dart';
import 'dispose_tracker.dart';

// Riverpod wiring of the microphone and output choice (WP188, K149). The
// choice is stored natively (the wake service reads it without Flutter).

/// Devices and the stored choice (overridden in tests with the fake).
final audioDevicesPortProvider = Provider<AudioDevicesPort>(
  (ref) => ChannelAudioDevicesPort(),
);

/// Connected devices: the list at the start, then a new one for every device
/// that comes or goes.
final audioDevicesProvider = StreamProvider<AudioDeviceList>((ref) async* {
  final port = ref.watch(audioDevicesPortProvider);
  // Listen first, so a change between reading and listening is not lost.
  final changes = StreamController<AudioDeviceList>();
  final sub = port.changes.listen(changes.add);
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(changes.close());
  });
  yield await port.devices();
  yield* changes.stream;
});

/// The chosen device per direction (`null` = system).
final audioSelectionProvider =
    AsyncNotifierProvider<AudioSelectionNotifier, AudioSelection>(
      AudioSelectionNotifier.new,
    );

/// Reads and stores the choice.
final class AudioSelectionNotifier extends AsyncNotifier<AudioSelection> {
  @override
  Future<AudioSelection> build() =>
      ref.watch(audioDevicesPortProvider).selection();

  /// Chooses [device] for [direction]; `null` = system. The state changes
  /// only after the choice was stored.
  Future<void> select(AudioDirection direction, AudioDevice? device) async {
    final current = await future;
    await ref.read(audioDevicesPortProvider).select(direction, device);
    state = AsyncData(current.withDirection(direction, device));
  }
}

/// What is used for [AudioDirection] right now: the chosen device if it is
/// connected, else the system ([AudioChoice.selectedMissing] tells which).
/// While devices or choice are not read yet: the system.
final audioChoiceProvider = Provider.family<AudioChoice, AudioDirection>((
  ref,
  direction,
) {
  final selected = ref.watch(audioSelectionProvider).value?.of(direction);
  final connected =
      ref.watch(audioDevicesProvider).value?.of(direction) ?? const [];
  return resolveAudioChoice(selected, connected);
});

/// The speech and tone output (WP188): [AudioplayersPlayback] while no output
/// device is chosen, the native `AudioTrack` with a chosen one (see
/// [RoutedPlayback]). The choice is cached from [audioSelectionProvider], so
/// the check per play costs nothing; while it loads or after a read error
/// the system route is used.
AudioPlayback createRoutedPlayback(
  Ref ref, {
  AudioPlayback? system,
  AudioPlayback? track,
}) {
  var chosen = false;
  ref.listen(audioSelectionProvider, (_, next) {
    chosen = next.value?.output != null;
  }, fireImmediately: true);
  final sys = system ?? AudioplayersPlayback();
  final trk = track ?? AudioTrackPlayback();
  final router = RoutedPlayback(
    system: sys,
    track: trk,
    hasChoice: () => chosen,
  );
  onDisposeTracked(ref, () async {
    await router.stop();
    if (sys is AudioplayersPlayback) await sys.dispose();
    if (trk is AudioTrackPlayback) await trk.dispose();
  });
  return router;
}
