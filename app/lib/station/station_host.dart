import 'dart:async';

import 'package:flutter/services.dart';

import '../platform/assistant_platform.dart';
import '../platform/channels.dart';
import '../platform/screen_protection.dart';
import 'station_display.dart';

/// What the station asks of the device (the platform side is Kotlin).
abstract interface class StationHost {
  /// Sets the screen: keep-on flag and window brightness.
  Future<void> applyDisplay(StationDisplay display);

  /// Asks to unlock (`KeyguardManager.requestDismissKeyguard`); `true` only
  /// if the device was unlocked.
  Future<bool> requestUnlock();

  /// Closes the station activity.
  Future<void> finish();

  /// The ambient light is low (`true`) or normal (`false`); from the light
  /// sensor on the Kotlin side.
  Stream<bool> get ambientDark;
}

/// [StationHost] over the window and assistant channels.
final class DeviceStationHost implements StationHost {
  /// Creates the host.
  DeviceStationHost(this._assistant, this._window);

  final AssistantPlatform _assistant;
  final ScreenProtection _window;
  final _dark = StreamController<bool>.broadcast(sync: true);
  bool _listening = false;

  @override
  Stream<bool> get ambientDark {
    if (!_listening) {
      _listening = true;
      const MethodChannel(stationChannelName)
          .setMethodCallHandler((call) async {
            if (call.method == 'ambient') {
              _dark.add((call.arguments as Map?)?['dark'] == true);
            }
            return null;
          });
    }
    return _dark.stream;
  }

  @override
  Future<void> applyDisplay(StationDisplay display) async {
    await _window.keepScreenOn(on: display.keepOn);
    await _window.setBrightness(
      ambient: display.brightness == StationBrightness.ambient,
    );
  }

  @override
  Future<bool> requestUnlock() => _assistant.requestUnlock();

  @override
  Future<void> finish() => _assistant.finish();
}
