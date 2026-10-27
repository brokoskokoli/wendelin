import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'channels.dart';

export 'channels.dart' show restrictedSettingsChannelName;

/// Bridge to the "restricted settings" state of Android 13+ (overridden in
/// tests, WP159).
final restrictedSettingsPlatformProvider = Provider<RestrictedSettingsPlatform>(
  (ref) => RestrictedSettingsPlatform(),
);

/// How the APK got onto the device.
enum InstallSource {
  /// Store or installer API (also `adb install`): not restricted.
  session,

  /// From a (downloaded) file via the file manager: restricted on Android 13+.
  file,

  /// Not readable (API < 33 or error).
  unknown;

  /// Parses the Kotlin name; anything unexpected is [unknown].
  static InstallSource parse(Object? name) => switch (name) {
    'session' => session,
    'file' => file,
    _ => unknown,
  };
}

/// What is known about the restricted settings (SMS permission, notification
/// access), WP159.
///
/// Android 13+ restricts SMS permission and notification access for an APK
/// installed from a file. The restriction itself cannot be read: the AppOp
/// `ACCESS_RESTRICTED_SETTINGS` throws a `SecurityException` for every
/// `AppOpsManager.checkOp*` variant in a normal app (measured on Android 15),
/// and a blocked request looks like "never asked". So the UI shows only a
/// conditional hint, see [RestrictedSettings.mayBeRestricted].
class RestrictedSettings {
  /// Creates a state.
  const RestrictedSettings({
    this.sdk,
    this.installSource = InstallSource.unknown,
  });

  /// Reads the answer of `restrictedSettings`. Missing or malformed data gives
  /// the fail-safe "unknown" (no hint).
  factory RestrictedSettings.fromChannel(Object? raw) {
    if (raw is! Map) return const RestrictedSettings();
    return RestrictedSettings(
      sdk: raw['sdk'] is int ? raw['sdk'] as int : null,
      installSource: InstallSource.parse(raw['installSource']),
    );
  }

  /// `Build.VERSION.SDK_INT`, `null` if unknown.
  final int? sdk;

  /// Install source.
  final InstallSource installSource;

  /// Whether Android may block SMS permission / notification access: only
  /// for an APK installed from a file. Store, installer API and `adb install`
  /// are not restricted; an unreadable source gives no hint (no false alarm).
  bool get mayBeRestricted => installSource == InstallSource.file;

  /// Equality for tests and state comparison.
  @override
  bool operator ==(Object other) =>
      other is RestrictedSettings &&
      other.sdk == sdk &&
      other.installSource == installSource;

  @override
  int get hashCode => Object.hash(sdk, installSource);
}

/// Restricted settings state and the app info page.
class RestrictedSettingsPlatform {
  /// Creates the bridge; `channel` is injectable for tests.
  RestrictedSettingsPlatform({
    this._channel = const MethodChannel(restrictedSettingsChannelName),
  });

  final MethodChannel _channel;

  /// Current state; "unknown" (no hint) on error or without plugin.
  Future<RestrictedSettings> state() async => RestrictedSettings.fromChannel(
    await _invoke<Object?>('restrictedSettings'),
  );

  /// Opens the app info page of Wendelin (the "Allow restricted settings"
  /// entry is in its menu). `false` if no page opened.
  Future<bool> openAppInfo() async =>
      await _invoke<bool>('openAppInfo') ?? false;

  Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
