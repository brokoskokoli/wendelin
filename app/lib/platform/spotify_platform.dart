import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:platform/platform.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

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
