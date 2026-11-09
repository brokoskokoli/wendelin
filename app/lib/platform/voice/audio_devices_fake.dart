import 'dart:async';

import 'audio_devices.dart';

/// In-memory [AudioDevicesPort] for tests: [connect] and [disconnect] play
/// plugging a device in and out. The selection lives as long as the fake, so
/// a second app start can be played by reusing it.
final class FakeAudioDevicesPort implements AudioDevicesPort {
  /// Creates the fake with [list] connected and [selected] chosen.
  FakeAudioDevicesPort({
    this._list = const AudioDeviceList(),
    this._selected = const AudioSelection(),
  });

  AudioDeviceList _list;
  AudioSelection _selected;
  final _changes = StreamController<AudioDeviceList>.broadcast();

  @override
  Stream<AudioDeviceList> get changes => _changes.stream;

  @override
  Future<AudioDeviceList> devices() async => _list;

  @override
  Future<AudioSelection> selection() async => _selected;

  @override
  Future<void> select(AudioDirection direction, AudioDevice? device) async =>
      _selected = _selected.withDirection(direction, device);

  /// A device is plugged in (replaces one with the same key: a reconnect
  /// with a new Android id has the same key).
  void connect(AudioDirection direction, AudioDevice device) {
    final others = _list.of(direction).where((d) => d.key != device.key);
    _set(direction, [...others, device]);
  }

  /// The device with [key] is gone.
  void disconnect(AudioDirection direction, String key) =>
      _set(direction, _list.of(direction).where((d) => d.key != key).toList());

  void _set(AudioDirection direction, List<AudioDevice> devices) {
    _list = direction == AudioDirection.input
        ? AudioDeviceList(input: devices, output: _list.output)
        : AudioDeviceList(input: _list.input, output: devices);
    _changes.add(_list);
  }

  /// Closes the change stream.
  Future<void> dispose() => _changes.close();
}
