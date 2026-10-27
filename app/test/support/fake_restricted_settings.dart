import 'package:wendelin/platform/restricted_settings_platform.dart';

/// Fake bridge for widget tests (WP159).
class FakeRestrictedSettingsPlatform extends RestrictedSettingsPlatform {
  /// State returned by [state].
  RestrictedSettings current = const RestrictedSettings();

  /// Number of [openAppInfo] calls.
  int appInfoOpened = 0;

  @override
  Future<RestrictedSettings> state() async => current;

  @override
  Future<bool> openAppInfo() async {
    appInfoOpened++;
    return true;
  }
}
