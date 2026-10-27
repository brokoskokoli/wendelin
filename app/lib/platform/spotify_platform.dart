import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform/platform.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channel_app_presence_port.dart' show appsChannelName;
import 'channel_authorization_browser.dart';

/// Wakes the Spotify app: `ACTION_VIEW` on `spotify:` addressed to the
/// Spotify package; if that is refused, the launcher entry of the app.
/// Returns `false` if Spotify is not installed or cannot be started.
final class IntentSpotifyLauncher implements SpotifyAppLauncher {
  /// Creates the launcher; [platform] is injectable for tests.
  const IntentSpotifyLauncher({this._platform});

  final Platform? _platform;

  @override
  Future<bool> wake() async {
    final onAndroid =
        _platform?.isAndroid ?? defaultTargetPlatform == TargetPlatform.android;
    if (!onAndroid) return false;
    const flags = [Flag.FLAG_ACTIVITY_NEW_TASK];
    try {
      await AndroidIntent(
        action: 'action_view',
        data: 'spotify:',
        package: spotifyAndroidPackage,
        flags: flags,
        platform: _platform,
      ).launch();
      return true;
    } on PlatformException {
      // Fall through to the launcher entry.
    } on UnsupportedError {
      return false;
    }
    try {
      await AndroidIntent(
        action: 'action_main',
        category: 'category_launcher',
        package: spotifyAndroidPackage,
        flags: flags,
        platform: _platform,
      ).launch();
      return true;
    } on PlatformException {
      return false;
    } on UnsupportedError {
      return false;
    }
  }
}

/// [SpotifyAuthBrowser] over the existing OAuth channel (Custom Tab,
/// `OAuthRedirectActivity`): turns its failures into [SpotifyBrowserException]s
/// (the settings screen words them).
final class ChannelSpotifyAuthBrowser implements SpotifyAuthBrowser {
  /// Creates the adapter over [browser].
  const ChannelSpotifyAuthBrowser([
    this.browser = const ChannelAuthorizationBrowser(),
  ]);

  /// The channel to the platform.
  final ChannelAuthorizationBrowser browser;

  @override
  Future<Uri> authorize(Uri url, Uri redirect) async {
    try {
      return await browser.authorize(url, redirect);
    } on AuthorizationBrowserException catch (e) {
      throw SpotifyBrowserException(switch (e.failure) {
        AuthorizationFailure.noBrowser => SpotifyBrowserFailure.noBrowser,
        AuthorizationFailure.cancelled => SpotifyBrowserFailure.cancelled,
        AuthorizationFailure.stateMismatch =>
          SpotifyBrowserFailure.stateMismatch,
        AuthorizationFailure.failed => SpotifyBrowserFailure.failed,
      });
    }
  }
}

/// [SpotifyHostDevice] over the apps channel (`deviceNames`, Kotlin
/// `AppsChannel`): the device name the user gave, the market name and the
/// model. Without the channel (other engine, test) it returns no names; the
/// session then falls back to the device type.
final class ChannelSpotifyHostDevice implements SpotifyHostDevice {
  /// Creates the adapter; [channel] is injectable for tests.
  const ChannelSpotifyHostDevice({
    this._channel = const MethodChannel(appsChannelName),
  });

  final MethodChannel _channel;

  @override
  Future<Set<String>> names() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('deviceNames');
      return {...?raw?.whereType<String>()};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }
}
