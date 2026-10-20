import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

export 'channels.dart' show stationChannelName;

/// [StationPort] over the Kotlin `StationChannel` (starts `StationActivity`).
final class ChannelStationPort implements StationPort {
  /// Creates the port; [channel] is injectable for tests.
  const ChannelStationPort({
    this._channel = const MethodChannel(stationChannelName),
  });

  final MethodChannel _channel;

  /// Unknown (`null`) counts as locked: fail closed.
  @override
  Future<bool> isLocked() => _call<bool>('isLocked').then((v) => v ?? true);

  @override
  Future<void> start() => _call<void>('start');

  Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on PlatformException {
      throw const PortException(
        PortErrorKind.unavailable,
        'Der Stationsmodus lässt sich gerade nicht starten.',
      );
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Den Stationsmodus gibt es hier nicht.',
      );
    }
  }
}
