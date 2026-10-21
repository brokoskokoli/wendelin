import 'dart:async';

import 'package:flutter/services.dart';

import 'channels.dart';

export 'channels.dart' show audioFocusChannelName;

/// The two audio focus requests of the app (Kotlin `AudioFocusKinds`).
enum AudioFocusKind {
  /// The whole spoken answer: other players get quieter and keep playing
  /// (`AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`).
  duck,

  /// The recording of a command: other players pause and resume afterwards
  /// (`AUDIOFOCUS_GAIN_TRANSIENT`).
  listen,
}

/// Another app took [kind]'s focus (`lost`) or gave it back (`!lost`).
final class AudioFocusChange {
  /// Creates the change.
  const AudioFocusChange(this.kind, {required this.lost});

  /// Which request it concerns.
  final AudioFocusKind kind;

  /// True: the focus is gone (also for a moment); false: it is back.
  final bool lost;

  @override
  String toString() => 'AudioFocusChange(${kind.name}, lost: $lost)';
}

/// Audio focus held by the app (replaceable in tests).
abstract interface class AudioFocusPort {
  /// Losses and gains of held focus (broadcast). Being asked to duck is not
  /// reported.
  Stream<AudioFocusChange> get changes;

  /// Requests [kind]; false if Android refused. Holding it twice is fine.
  Future<bool> acquire(AudioFocusKind kind);

  /// Gives [kind] back (no effect if not held).
  Future<void> release(AudioFocusKind kind);
}

/// [AudioFocusPort] over `AudioManager` (Kotlin `AudioFocusChannel`). Errors
/// and a missing platform side are swallowed: no focus only means other
/// players keep their volume.
final class ChannelAudioFocusPort implements AudioFocusPort {
  /// Creates the port; [channel] is injectable for tests.
  ChannelAudioFocusPort({
    this._channel = const MethodChannel(audioFocusChannelName),
  }) {
    _changes = StreamController<AudioFocusChange>.broadcast(
      onListen: () => _channel.setMethodCallHandler(_onCall),
      onCancel: () => _channel.setMethodCallHandler(null),
    );
  }

  final MethodChannel _channel;
  late final StreamController<AudioFocusChange> _changes;

  @override
  Stream<AudioFocusChange> get changes => _changes.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'focusChanged') _focusChanged(call.arguments);
  }

  void _focusChanged(Object? args) {
    if (args is! Map) return;
    final kind = AudioFocusKind.values.asNameMap()[args['kind']];
    final state = args['state'];
    if (kind == null || (state != 'lost' && state != 'gained')) return;
    _changes.add(AudioFocusChange(kind, lost: state == 'lost'));
  }

  @override
  Future<bool> acquire(AudioFocusKind kind) async {
    try {
      return await _channel.invokeMethod<bool>('acquire', {
            'kind': kind.name,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> release(AudioFocusKind kind) async {
    try {
      await _channel.invokeMethod<void>('release', {'kind': kind.name});
    } on PlatformException {
      // Nothing to give back.
    } on MissingPluginException {
      // No platform side (tests, other platforms).
    }
  }
}

/// The call path for the spoken answer (WP118, K88; Kotlin `SpeechRoute`):
/// audio mode `MODE_IN_COMMUNICATION` and the output on the speaker unless a
/// headset or Bluetooth device is active.
abstract interface class SpeechRoutePort {
  /// Switches to the call path; returns the output (`speaker`, `external`),
  /// `null` if that failed. Asking twice is fine.
  Future<String?> enter();

  /// Restores the audio state from before [enter] (no effect if not entered).
  Future<void> leave();
}

/// [SpeechRoutePort] over the audio focus channel. Errors and a missing
/// platform side are swallowed: the answer is spoken in the normal path then.
final class ChannelSpeechRoutePort implements SpeechRoutePort {
  /// Creates the port; [channel] is injectable for tests.
  ChannelSpeechRoutePort({
    this._channel = const MethodChannel(audioFocusChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<String?> enter() async {
    try {
      return await _channel.invokeMethod<String>('enterCommunication');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// `AudioManager.mode` right now (device tests), `null` if unknown.
  Future<int?> audioMode() async {
    try {
      return await _channel.invokeMethod<int>('audioMode');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> leave() async {
    try {
      await _channel.invokeMethod<void>('leaveCommunication');
    } on PlatformException {
      // Nothing to restore.
    } on MissingPluginException {
      // No platform side (tests, other platforms).
    }
  }
}
