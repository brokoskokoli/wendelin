import 'dart:async';

import 'package:flutter/services.dart';

import 'channels.dart';

export 'channels.dart' show memoryChannelName;

/// Android's `onTrimMemory` levels (Kotlin `MemoryChannel`), pushed to
/// Dart (WP103). The models of the recognizer and the voice are freed
/// when [isMemoryPressure] says so.
abstract interface class MemoryTrimSource {
  /// The `ComponentCallbacks2.TRIM_MEMORY_*` levels as they arrive.
  Stream<int> get levels;
}

/// [MemoryTrimSource] on the platform channel. Where the channel is
/// missing (tests, other platforms) nothing arrives.
final class ChannelMemoryTrim implements MemoryTrimSource {
  /// Creates the source; [channel] is injectable for tests.
  ChannelMemoryTrim({this._channel = const MethodChannel(memoryChannelName)});

  final MethodChannel _channel;
  final _levels = StreamController<int>.broadcast();
  bool _listening = false;

  @override
  Stream<int> get levels {
    if (!_listening) {
      _listening = true;
      try {
        _channel.setMethodCallHandler((call) async {
          final args = call.arguments;
          final level = args is Map ? args['level'] : null;
          if (call.method == 'trim' && level is int) _levels.add(level);
        });
      } on Object {
        // No binding yet (unit tests without a Flutter binding).
      }
    }
    return _levels.stream;
  }
}
