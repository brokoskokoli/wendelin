import 'dart:async';

import 'package:flutter/services.dart';

import 'channels.dart';

/// Ambient-light events from the Kotlin `StationChannel` (`ambient` calls).
///
/// A [MethodChannel] has one handler. The newest listener wins: a second
/// instance takes the handler over, and [dispose] of the older one leaves
/// the newer handler in place.
final class StationAmbientChannel {
  /// Creates the receiver; [channel] is injectable for tests.
  StationAmbientChannel({
    this._channel = const MethodChannel(stationChannelName),
  });

  static final _owners = Expando<StationAmbientChannel>('station owner');

  final MethodChannel _channel;
  final _dark = StreamController<bool>.broadcast(sync: true);
  bool _listening = false;
  bool _disposed = false;

  /// `true` when the light sensor reports a dark room. Registers the handler
  /// on first access.
  Stream<bool> get dark {
    if (!_listening && !_disposed) {
      _listening = true;
      _owners[_channel] = this;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'ambient') {
          _dark.add((call.arguments as Map?)?['dark'] == true);
        }
        return null;
      });
    }
    return _dark.stream;
  }

  /// Removes the handler (only if it is still ours) and closes the stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (identical(_owners[_channel], this)) {
      _owners[_channel] = null;
      _channel.setMethodCallHandler(null);
    }
    unawaited(_dark.close());
  }
}
