import 'package:flutter/services.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import 'channels.dart';

export 'channels.dart' show authChannelName;

/// Why the login in the browser did not complete.
enum AuthorizationFailure {
  /// No browser is installed (AOSP image without a browser).
  noBrowser,

  /// The user closed the browser without finishing.
  cancelled,

  /// Anything else (platform error, missing plugin).
  failed,
}

/// Thrown by [ChannelAuthorizationBrowser.authorize].
final class AuthorizationBrowserException implements Exception {
  /// Creates the failure.
  const AuthorizationBrowserException(this.failure, this.message);

  /// What went wrong.
  final AuthorizationFailure failure;

  /// German text.
  final String message;

  @override
  String toString() => 'AuthorizationBrowserException(${failure.name})';
}

/// [AuthorizationBrowser] over the Kotlin `AuthChannel`: opens the login
/// page in a Custom Tab (`androidx.browser`, no Google services, K7) or, if
/// no browser supports Custom Tabs, in any browser. The redirect to the
/// app's scheme reaches `OAuthRedirectActivity`, which hands it back here.
/// The platform only accepts a redirect with the login's `state`;
/// `McpOAuthFlow` checks `state` and issuer again.
final class ChannelAuthorizationBrowser implements AuthorizationBrowser {
  /// Creates the browser; [channel] is injectable for tests.
  const ChannelAuthorizationBrowser({
    this._channel = const MethodChannel(authChannelName),
  });

  final MethodChannel _channel;

  /// Whether a browser is installed that can show the login page.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens [url] (https) in the browser and returns at once; the answer
  /// comes elsewhere (Google Tasks login: a local server in Dart).
  /// Returns `false` if no browser can show it.
  Future<bool> open(Uri url) async {
    if (!url.isScheme('https')) {
      throw ArgumentError.value(url.scheme, 'url', 'nur https');
    }
    try {
      return await _channel.invokeMethod<bool>('open', {
            'url': url.toString(),
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Uri> authorize(Uri url, Uri redirect) async {
    if (!url.isScheme('https') && !url.isScheme('http')) {
      throw ArgumentError.value(url.scheme, 'url', 'nur http(s)');
    }
    try {
      final back = await _channel.invokeMethod<String>('authorize', {
        'url': url.toString(),
        'redirect': redirect.toString(),
        // Kotlin hands back only the redirect with this state; others
        // (e.g. opened by another app) are ignored.
        'state': url.queryParameters['state'] ?? '',
      });
      final uri = back == null ? null : Uri.tryParse(back);
      if (uri == null) {
        throw const AuthorizationBrowserException(
          AuthorizationFailure.failed,
          'Keine Rückleitung erhalten.',
        );
      }
      return uri;
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'no_browser' => const AuthorizationBrowserException(
          AuthorizationFailure.noBrowser,
          'Kein Browser installiert.',
        ),
        'cancelled' => const AuthorizationBrowserException(
          AuthorizationFailure.cancelled,
          'Anmeldung abgebrochen.',
        ),
        _ => AuthorizationBrowserException(
          AuthorizationFailure.failed,
          'Anmeldung nicht möglich (${e.code}).',
        ),
      };
    } on MissingPluginException {
      throw const AuthorizationBrowserException(
        AuthorizationFailure.failed,
        'Anmeldung ist hier nicht möglich.',
      );
    }
  }
}
