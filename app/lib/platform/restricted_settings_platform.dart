import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'channels.dart';

export 'channels.dart' show restrictedSettingsChannelName;

/// Bridge to the "restricted settings" state of Android 13+ (overridden in
/// tests, WP159).
final restrictedSettingsPlatformProvider = Provider<RestrictedSettingsPlatform>(
  (ref) => RestrictedSettingsPlatform(),
);

/// Mode of the AppOp `ACCESS_RESTRICTED_SETTINGS`.
enum RestrictedOpMode {
  /// The user released the restricted settings.
  allowed,

  /// Android blocks SMS permission and notification access.
  ignored,

  /// Not (yet) decided; Android sets `ignored` at the first blocked attempt.
  defaultMode,

  /// Not readable (API < 33, op hidden, `SecurityException`, unknown value).
  unknown;

  /// Parses the Kotlin name; anything unexpected is [unknown].
  static RestrictedOpMode parse(Object? name) => switch (name) {
    'allowed' => allowed,
    'ignored' => ignored,
    'default' => defaultMode,
    _ => unknown,
  };
}

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

/// State of the restricted settings (SMS permission, notification access).
class RestrictedSettings {
  /// Creates a state.
  const RestrictedSettings({
    this.sdk,
    this.opMode = RestrictedOpMode.unknown,
    this.installSource = InstallSource.unknown,
  });

  /// Reads the answer of `restrictedSettings`. Missing or malformed data gives
  /// the fail-safe "unknown" (no hint, see [restricted]).
  factory RestrictedSettings.fromChannel(Object? raw) {
    if (raw is! Map) return const RestrictedSettings();
    return RestrictedSettings(
      sdk: raw['sdk'] is int ? raw['sdk'] as int : null,
      opMode: RestrictedOpMode.parse(raw['opMode']),
      installSource: InstallSource.parse(raw['installSource']),
    );
  }

  /// `Build.VERSION.SDK_INT`, `null` if unknown.
  final int? sdk;

  /// AppOp mode.
  final RestrictedOpMode opMode;

  /// Install source.
  final InstallSource installSource;

  /// Whether Android blocks SMS permission / notification access now.
  bool get restricted => isRestricted(opMode, installSource);

  /// Equality for tests and state comparison.
  @override
  bool operator ==(Object other) =>
      other is RestrictedSettings &&
      other.sdk == sdk &&
      other.opMode == opMode &&
      other.installSource == installSource;

  @override
  int get hashCode => Object.hash(sdk, opMode, installSource);
}

/// Decides whether the restriction is active.
///
/// - `ignored` is proof: true.
/// - `allowed` / `default`: false. (`default` before the first blocked
///   attempt is not detectable; the hint then appears after that attempt.)
/// - `unknown`: true only for an APK installed from a file, because that is
///   the source Android restricts. Otherwise false: no false alarm.
///
/// The result of the permission request is deliberately not used: a blocked
/// request looks like "never asked" (measured on Android 15).
bool isRestricted(RestrictedOpMode op, InstallSource source) => switch (op) {
  RestrictedOpMode.ignored => true,
  RestrictedOpMode.allowed || RestrictedOpMode.defaultMode => false,
  RestrictedOpMode.unknown => source == InstallSource.file,
};

/// Restricted settings state and the app info page.
class RestrictedSettingsPlatform {
  /// Creates the bridge; `channel` is injectable for tests.
  RestrictedSettingsPlatform({
    this._channel = const MethodChannel(restrictedSettingsChannelName),
  });

  final MethodChannel _channel;

  /// Current state; "unknown" (not restricted) on error or without plugin.
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
