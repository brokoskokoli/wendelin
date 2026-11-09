import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../channels.dart';

export '../channels.dart' show audioDevicesChannelName;

/// Which way the sound goes (WP188).
enum AudioDirection {
  /// A microphone.
  input,

  /// A speaker, headphones or box.
  output,
}

/// Kind of a device (wire name of Kotlin `AudioDevicePick`); unknown names are [other].
enum AudioDeviceType {
  /// Built-in microphone.
  builtinMic('builtin_mic'),

  /// Built-in speaker.
  builtinSpeaker('builtin_speaker'),

  /// Earpiece of the phone.
  earpiece('earpiece'),

  /// Headset or headphones on the jack.
  wiredHeadset('wired_headset'),

  /// USB audio.
  usb('usb'),

  /// Analog or digital line.
  line('line'),

  /// Bluetooth headset profile (phone call quality, microphone).
  bluetoothSco('bluetooth_sco'),

  /// Bluetooth music profile (output only).
  bluetoothA2dp('bluetooth_a2dp'),

  /// Bluetooth LE audio.
  bluetoothLe('bluetooth_le'),

  /// Hearing aid.
  hearingAid('hearing_aid'),

  /// Anything else.
  other('');

  const AudioDeviceType(this.wire);

  /// Name on the channel.
  final String wire;

  /// Parses a wire name; unknown gives [other].
  static AudioDeviceType parse(Object? wire) =>
      values.firstWhere((t) => t.wire == wire, orElse: () => other);
}

/// A choosable device. [key] is stable over reconnects (never Android's device
/// id) and opaque: the UI shows only [name] and [type]. The address of the
/// device never reaches Dart.
@immutable
final class AudioDevice {
  /// Creates the device.
  const AudioDevice({
    required this.key,
    required this.type,
    required this.name,
  });

  /// Reads a channel map; `null` if the key is missing.
  static AudioDevice? fromChannel(Object? value) {
    if (value is! Map) return null;
    final key = value['key'];
    if (key is! String || key.isEmpty) return null;
    final name = value['name'];
    return AudioDevice(
      key: key,
      type: AudioDeviceType.parse(value['type']),
      name: name is String ? name : '',
    );
  }

  /// Stable key (type, product name, hash of the address).
  final String key;

  /// Kind of device.
  final AudioDeviceType type;

  /// Product name (may be empty).
  final String name;

  @override
  bool operator ==(Object other) =>
      other is AudioDevice &&
      other.key == key &&
      other.type == type &&
      other.name == name;

  @override
  int get hashCode => Object.hash(key, type, name);

  // No key in the text: logs must stay free of device identifiers.
  @override
  String toString() => 'AudioDevice(${type.name})';
}

/// Devices that are connected right now, per direction.
@immutable
final class AudioDeviceList {
  /// Creates the list.
  const AudioDeviceList({this.input = const [], this.output = const []});

  /// Reads the channel answer; anything else is empty.
  factory AudioDeviceList.fromChannel(Object? value) {
    if (value is! Map) return const AudioDeviceList();
    List<AudioDevice> read(Object? list) => [
      if (list is List)
        for (final e in list) ?AudioDevice.fromChannel(e),
    ];
    return AudioDeviceList(
      input: read(value['input']),
      output: read(value['output']),
    );
  }

  /// Microphones.
  final List<AudioDevice> input;

  /// Outputs.
  final List<AudioDevice> output;

  /// The devices of [direction].
  List<AudioDevice> of(AudioDirection direction) =>
      direction == AudioDirection.input ? input : output;

  @override
  bool operator ==(Object other) =>
      other is AudioDeviceList &&
      listEquals(other.input, input) &&
      listEquals(other.output, output);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(input), Object.hashAll(output));
}

/// The chosen device per direction; `null` is the system default. A chosen
/// device keeps its name and type, so a missing one can still be shown.
@immutable
final class AudioSelection {
  /// Creates the selection (default: system for both).
  const AudioSelection({this.input, this.output});

  /// Reads the channel answer; anything else is the system default.
  factory AudioSelection.fromChannel(Object? value) {
    if (value is! Map) return const AudioSelection();
    return AudioSelection(
      input: AudioDevice.fromChannel(value['input']),
      output: AudioDevice.fromChannel(value['output']),
    );
  }

  /// Chosen microphone, `null` = system.
  final AudioDevice? input;

  /// Chosen output, `null` = system.
  final AudioDevice? output;

  /// The choice for [direction].
  AudioDevice? of(AudioDirection direction) =>
      direction == AudioDirection.input ? input : output;

  /// Copy with [direction] set to [device] (`null` = system).
  AudioSelection withDirection(AudioDirection direction, AudioDevice? device) =>
      direction == AudioDirection.input
      ? AudioSelection(input: device, output: output)
      : AudioSelection(input: input, output: device);

  @override
  bool operator ==(Object other) =>
      other is AudioSelection && other.input == input && other.output == output;

  @override
  int get hashCode => Object.hash(input, output);
}

/// What is used for one direction right now (WP188, K149).
@immutable
final class AudioChoice {
  /// Creates the choice.
  const AudioChoice({this.selected, this.active});

  /// What the user chose, `null` = system.
  final AudioDevice? selected;

  /// The device in use: [selected] if it is connected, else `null` = system.
  final AudioDevice? active;

  /// A device is chosen but not connected: the system is used meanwhile.
  bool get selectedMissing => selected != null && active == null;
}

/// The device to use: the connected one with [selected]'s key, else the
/// system. Matching by key, never by object or Android id, so the choice
/// survives reconnecting and comes back by itself.
AudioChoice resolveAudioChoice(
  AudioDevice? selected,
  List<AudioDevice> connected,
) => AudioChoice(
  selected: selected,
  active: selected == null
      ? null
      : connected.where((d) => d.key == selected.key).firstOrNull,
);

/// Devices and their choice (replaceable in tests; Kotlin `AudioDevicesChannel`).
abstract interface class AudioDevicesPort {
  /// The devices connected right now. Needs no permission.
  Future<AudioDeviceList> devices();

  /// A device came or went (broadcast); the event carries the new list.
  Stream<AudioDeviceList> get changes;

  /// The stored choice (survives restarts, readable by the service).
  Future<AudioSelection> selection();

  /// Stores the choice for [direction]; `null` = system.
  Future<void> select(AudioDirection direction, AudioDevice? device);
}

/// [AudioDevicesPort] over the platform channel. Without a platform side
/// (tests, other platforms) it answers: no devices, system default.
final class ChannelAudioDevicesPort implements AudioDevicesPort {
  /// Creates the port; [channel] is injectable for tests.
  ChannelAudioDevicesPort({
    this._channel = const MethodChannel(audioDevicesChannelName),
  }) {
    _changes = StreamController<AudioDeviceList>.broadcast(
      onListen: () => _channel.setMethodCallHandler(_onCall),
      onCancel: () => _channel.setMethodCallHandler(null),
    );
  }

  final MethodChannel _channel;
  late final StreamController<AudioDeviceList> _changes;

  @override
  Stream<AudioDeviceList> get changes => _changes.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'devicesChanged') _changes.add(await devices());
  }

  @override
  Future<AudioDeviceList> devices() async {
    try {
      return AudioDeviceList.fromChannel(
        await _channel.invokeMethod<Object>('devices'),
      );
    } on PlatformException {
      return const AudioDeviceList();
    } on MissingPluginException {
      return const AudioDeviceList();
    }
  }

  @override
  Future<AudioSelection> selection() async {
    try {
      return AudioSelection.fromChannel(
        await _channel.invokeMethod<Object>('selection'),
      );
    } on PlatformException {
      return const AudioSelection();
    } on MissingPluginException {
      return const AudioSelection();
    }
  }

  @override
  Future<void> select(AudioDirection direction, AudioDevice? device) async {
    // Errors are not swallowed: a choice that was not stored must show.
    await _channel.invokeMethod<void>('setSelection', {
      'direction': direction.name,
      'key': device?.key,
      'type': device?.type.wire,
      'name': device?.name,
    });
  }
}
