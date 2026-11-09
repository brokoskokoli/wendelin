// WP188 C1: Verdrahtung der Ausgabe: Wahl aus dem Speicher-Provider steuert
// die Weiche; Lesefehler und Laden sind System.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/audio_devices_providers.dart';
import 'package:wendelin/platform/voice/audio_devices.dart';
import 'package:wendelin/platform/voice/audio_devices_fake.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/voice/sherpa_tts.dart';

final class _Fake implements AudioPlayback {
  var plays = 0;

  @override
  Future<void> play(Wav wav) async => plays++;

  @override
  Future<void> stop() async {}
}

final class _FailingSelection implements AudioDevicesPort {
  @override
  Stream<AudioDeviceList> get changes => const Stream.empty();

  @override
  Future<AudioDeviceList> devices() async => const AudioDeviceList();

  @override
  Future<AudioSelection> selection() async => throw StateError('x');

  @override
  Future<void> select(AudioDirection direction, AudioDevice? device) async {}
}

const _device = AudioDevice(key: 'k', type: AudioDeviceType.usb, name: 'Box');

void main() {
  final wav = Wav(Int16List(4));
  late _Fake system;
  late _Fake track;
  final provider = Provider<AudioPlayback>(
    (ref) => createRoutedPlayback(ref, system: system, track: track),
  );

  setUp(() {
    system = _Fake();
    track = _Fake();
  });

  ProviderContainer container(AudioDevicesPort port) {
    final c = ProviderContainer(
      overrides: [audioDevicesPortProvider.overrideWithValue(port)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('nothing stored: system', () async {
    final c = container(FakeAudioDevicesPort());
    final p = c.read(provider);
    await c.read(audioSelectionProvider.future);
    await p.play(wav);
    expect((system.plays, track.plays), (1, 0));
  });

  test('output stored: track, also after a change at runtime', () async {
    final c = container(FakeAudioDevicesPort());
    final p = c.read(provider);
    await c.read(audioSelectionProvider.future);
    await c
        .read(audioSelectionProvider.notifier)
        .select(AudioDirection.output, _device);
    await p.play(wav);
    expect((system.plays, track.plays), (0, 1));
    await c
        .read(audioSelectionProvider.notifier)
        .select(AudioDirection.output, null);
    await p.play(wav);
    expect((system.plays, track.plays), (1, 1));
  });

  test('only the input stored: system', () async {
    final c = container(
      FakeAudioDevicesPort(selected: const AudioSelection(input: _device)),
    );
    final p = c.read(provider);
    await c.read(audioSelectionProvider.future);
    await p.play(wav);
    expect((system.plays, track.plays), (1, 0));
  });

  test('read error of the selection: system, no hang', () async {
    final c = container(_FailingSelection());
    final p = c.read(provider);
    await c.read(audioSelectionProvider.future).then((_) {}, onError: (_) {});
    await p.play(wav).timeout(const Duration(seconds: 5));
    expect((system.plays, track.plays), (1, 0));
  });

  test('still loading: system', () async {
    final c = container(FakeAudioDevicesPort());
    final p = c.read(provider);
    await p.play(wav);
    expect((system.plays, track.plays), (1, 0));
  });

  test('stored and still loading: the first clip goes to the track', () async {
    final c = container(
      FakeAudioDevicesPort(selected: const AudioSelection(output: _device)),
    );
    final p = c.read(provider);
    expect(c.read(audioSelectionProvider).hasValue, isFalse);
    await p.play(wav);
    expect((system.plays, track.plays), (0, 1));
  });

  test(
    'nothing stored, already read: the system play starts at once',
    () async {
      final c = container(FakeAudioDevicesPort());
      final p = c.read(provider);
      await c.read(audioSelectionProvider.future);
      unawaited(p.play(wav));
      expect(
        system.plays,
        1,
        reason: 'no extra await once the choice is known',
      );
    },
  );
}
