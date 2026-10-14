import 'package:flutter/services.dart';

import 'channels.dart';

export 'channels.dart' show windowChannelName;

/// Screen content protection (`FLAG_SECURE`: no screenshots or screen
/// recording, blank in the app switcher). The assistant overlay always
/// has it; the main app only if the user switches it on.
class ScreenProtection {
  /// Creates the bridge; `channel` is injectable for tests.
  const ScreenProtection({
    this._channel = const MethodChannel(windowChannelName),
  });

  final MethodChannel _channel;

  /// Protects the window ([secure]) or not. Without a platform side (tests,
  /// desktop) nothing happens.
  Future<void> apply({required bool secure}) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Kein Android-Fenster.
    }
  }

  /// Keeps the screen on while a long run needs it (calibration, WP60).
  Future<void> keepScreenOn({required bool on}) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {'on': on});
    } on MissingPluginException {
      // Kein Android-Fenster.
    }
  }
}
