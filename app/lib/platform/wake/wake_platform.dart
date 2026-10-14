import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../channels.dart';

export '../channels.dart' show wakeChannelName;

/// Bridge to the wake word service (overridden in tests).
final wakePlatformProvider = Provider<WakePlatform>((ref) => WakePlatform());

/// When the wake word listens (setting „Bedingung“).
enum WakeCondition {
  /// Only while the device charges (default).
  charging,

  /// Always, as long as the wake word is on.
  always;

  /// Parses a stored name; unknown values give [charging].
  static WakeCondition parse(Object? name) =>
      values.where((c) => c.name == name).firstOrNull ?? charging;
}

/// State of the service as Kotlin reports it.
@immutable
final class WakeServiceStatus {
  /// Creates the status.
  const WakeServiceStatus({
    this.running = false,
    this.enabled,
    this.offByUser = false,
    this.holdsRole = false,
    this.charging = false,
    this.pausedUntil,
    this.lastStop,
  });

  /// Reads the channel answer; anything else is the default (not running).
  factory WakeServiceStatus.fromChannel(Object? value) {
    if (value is! Map) return const WakeServiceStatus();
    final until = value['pausedUntil'];
    return WakeServiceStatus(
      running: value['running'] == true,
      enabled: value['enabled'] is bool ? value['enabled'] as bool : null,
      offByUser: value['offByUser'] == true,
      holdsRole: value['holdsRole'] == true,
      charging: value['charging'] == true,
      pausedUntil: until is int && until > 0
          ? DateTime.fromMillisecondsSinceEpoch(until)
          : null,
      lastStop: value['lastStop'] is String
          ? value['lastStop'] as String
          : null,
    );
  }

  /// The service is alive in the process.
  final bool running;

  /// The switch as Kotlin knows it (the notification's „Aus“ changes it
  /// behind the app's back); `null` if unknown.
  final bool? enabled;

  /// The notification's „Aus“ switched it off (not the app). Only this
  /// is adopted: a plain `enabled == false` may be an answer read before
  /// the app's own switch-on.
  final bool offByUser;

  /// Wendelin is the system assistant (required for the wake word).
  final bool holdsRole;

  /// The device charges.
  final bool charging;

  /// End of „Pause 1 h“, if paused.
  final DateTime? pausedUntil;

  /// Why the service stopped last (log code).
  final String? lastStop;
}

/// The main app's side of the wake word service: mirrors the settings to
/// Kotlin (the service reads them without a database) and starts or stops
/// it accordingly. Works only on Android.
class WakePlatform {
  /// Creates the bridge; `channel` is injectable for tests.
  WakePlatform({this._channel = const MethodChannel(wakeChannelName)});

  final MethodChannel _channel;

  /// Sets the wake word settings; Kotlin starts or stops the service.
  Future<void> configure({
    required bool enabled,
    required WakeCondition condition,
    required bool verify,
  }) async {
    try {
      await _channel.invokeMethod<void>('configure', {
        'enabled': enabled,
        'mode': condition.name,
        'verify': verify,
      });
    } on MissingPluginException {
      // Not on Android (tests, desktop).
    } on PlatformException {
      // Reported through the log of the service.
    }
  }

  /// State of the service.
  Future<WakeServiceStatus> status() async {
    try {
      return WakeServiceStatus.fromChannel(
        await _channel.invokeMethod<Object?>('status'),
      );
    } on MissingPluginException {
      return const WakeServiceStatus();
    } on PlatformException {
      return const WakeServiceStatus();
    }
  }
}
