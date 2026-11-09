import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/voice/audio_devices.dart';

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
