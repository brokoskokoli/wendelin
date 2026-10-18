import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../common/port_exception.dart';
import 'spotify_api.dart';

/// Redirect address the user enters in the Spotify developer app. The app
/// registers it in the manifest (`OAuthRedirectActivity`).
final spotifyRedirect = Uri.parse('app.wendelin://oauth/spotify');

/// Scopes of the login: read the playback state, control playback.
const spotifyScopes = [
  'user-read-playback-state',
  'user-modify-playback-state',
  'user-read-currently-playing',
];

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A random string of [length] unreserved characters (RFC 7636 §4.1).
String _randomToken(Random random, int length) => String.fromCharCodes([
  for (var i = 0; i < length; i++)
    _unreserved.codeUnitAt(random.nextInt(_unreserved.length)),
]);

/// PKCE challenge `BASE64URL(SHA256(verifier))` without padding.
String spotifyChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

/// Whether [id] looks like a Spotify Client-ID (32 hex characters).
bool isSpotifyClientId(String id) => RegExp(r'^[0-9a-f]{32}$').hasMatch(id);

/// Login with the user's own Spotify developer app (Authorization Code with
/// PKCE, no client secret).
final class SpotifyLogin {
  /// Creates the login; [random] must be `Random.secure()` outside tests.
  SpotifyLogin(this.api, this.secrets, this.browser, {Random? random})
    : _random = random ?? Random.secure();

  /// The Web API and its token endpoint.
  final SpotifyApi api;

  /// Where Client-ID and tokens are stored.
  final SpotifySecrets secrets;

  /// Shows the login page.
  final SpotifyAuthBrowser browser;

  final Random _random;

  /// The login address for [clientId] (exposed for tests).
  Uri authorizationUrl(String clientId, String state, String verifier) =>
      Uri.https('accounts.spotify.com', '/authorize', {
        'response_type': 'code',
        'client_id': clientId,
        'scope': spotifyScopes.join(' '),
        'redirect_uri': spotifyRedirect.toString(),
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': spotifyChallenge(verifier),
      });

  /// Logs in with [clientId]. Returns `null` on success (Client-ID and
  /// tokens are stored then), else a German message; nothing is stored on a
  /// failure.
  Future<String?> signIn(String clientId) async {
    final id = clientId.trim().toLowerCase();
    if (!isSpotifyClientId(id)) {
      return 'Die Client-ID besteht aus 32 Zeichen (Ziffern und Buchstaben '
          'a–f). Bitte aus dem Entwickler-Dashboard kopieren.';
    }
    final verifier = _randomToken(_random, 64);
    final state = _randomToken(_random, 32);
    try {
      final back = await browser.authorize(
        authorizationUrl(id, state, verifier),
        spotifyRedirect,
      );
      final params = back.queryParameters;
      if (params['state'] != state) {
        return 'Anmeldung abgelehnt: Antwort gehört nicht zu dieser Anmeldung.';
      }
      if (params['error'] != null) {
        return params['error'] == 'access_denied'
            ? 'Anmeldung abgebrochen: Zugriff nicht erlaubt.'
            : 'Spotify hat die Anmeldung abgelehnt.';
      }
      final code = params['code'];
      if (code == null || code.isEmpty) {
        return 'Spotify hat keinen Code geschickt.';
      }
      final auth = await api.exchangeCode(
        clientId: id,
        code: code,
        verifier: verifier,
        redirect: spotifyRedirect,
      );
      await secrets.saveClientId(id);
      await secrets.saveAuth(auth);
      return null;
    } on PortException catch (e) {
      return e.message;
    }
  }

  /// Deletes tokens and Client-ID.
  Future<void> signOut() async {
    await secrets.saveAuth(null);
    await secrets.saveClientId(null);
  }
}
