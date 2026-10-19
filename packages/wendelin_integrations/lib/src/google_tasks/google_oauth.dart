import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import '../common/port_exception.dart';

/// OAuth scope of the Tasks API (read and write).
const googleTasksScope = 'https://www.googleapis.com/auth/tasks';

/// The OAuth client the user created in their own Google Cloud project
/// (type „Desktop“). Both parts are secrets: [toString] hides them.
@immutable
final class GoogleClient {
  /// Creates the client.
  const GoogleClient({required this.id, required this.secret});

  /// Client ID (`….apps.googleusercontent.com`).
  final String id;

  /// Client secret (Google needs it for desktop clients, PKCE or not).
  final String secret;

  @override
  bool operator ==(Object other) =>
      other is GoogleClient && other.id == id && other.secret == secret;

  @override
  int get hashCode => Object.hash(id, secret);

  @override
  String toString() => 'GoogleClient(<verborgen>)';
}

/// A short-lived access token. Kept in memory only.
@immutable
final class GoogleAccessToken {
  /// Creates the token.
  const GoogleAccessToken(this.token, this.expiresAt);

  /// Bearer token of the Tasks API.
  final String token;

  /// When [token] ends.
  final DateTime expiresAt;

  /// Whether the token is still good at [now] (with a minute to spare).
  bool validAt(DateTime now) =>
      now.isBefore(expiresAt.subtract(const Duration(minutes: 1)));

  @override
  String toString() => 'GoogleAccessToken(<verborgen>)';
}

/// Result of a code exchange or refresh.
@immutable
final class GoogleTokenSet {
  /// Creates the result.
  const GoogleTokenSet(this.access, {this.refreshToken});

  /// The new access token.
  final GoogleAccessToken access;

  /// The long-lived token; `null` on a refresh that does not rotate it.
  final String? refreshToken;

  @override
  String toString() => 'GoogleTokenSet(<verborgen>)';
}

/// Where the Google secrets live (app: `SecretStore`). Never SQLite,
/// settings JSON, logs or exports.
abstract interface class GoogleTasksSecrets {
  /// The user's OAuth client, or `null`.
  Future<GoogleClient?> client();

  /// Replaces the client; `null` deletes it.
  Future<void> saveClient(GoogleClient? client);

  /// The refresh token, or `null` when not logged in.
  Future<String?> refreshToken();

  /// Replaces the refresh token; `null` deletes it.
  Future<void> saveRefreshToken(String? token);
}

/// Google's OAuth endpoints (authorization page address, token, revoke).
///
/// Throws `PortException` only, German texts without tokens, secrets or
/// response bodies: `permissionDenied` (code or refresh token refused,
/// client wrong), `rejected` (scope missing), `unavailable` (network, 5xx),
/// `failed` (unexpected answer).
abstract interface class GoogleOAuthApi {
  /// Exchanges the login [code] (PKCE [verifier], loopback [redirect]).
  Future<GoogleTokenSet> exchangeCode({
    required GoogleClient client,
    required String code,
    required String verifier,
    required Uri redirect,
  });

  /// A new access token from [refreshToken].
  Future<GoogleTokenSet> refresh(GoogleClient client, String refreshToken);

  /// Revokes [token] at Google (best effort; callers ignore failures).
  Future<void> revoke(String token);
}

/// Address of Google's login page.
final googleAuthorizationEndpoint = Uri.parse(
  'https://accounts.google.com/o/oauth2/v2/auth',
);

/// [GoogleOAuthApi] over HTTPS against `oauth2.googleapis.com`.
final class HttpGoogleOAuthApi implements GoogleOAuthApi {
  /// Creates the client. [clock] makes expiry testable.
  HttpGoogleOAuthApi({
    http.Client? client,
    Uri? tokenEndpoint,
    Uri? revokeEndpoint,
    this.timeout = const Duration(seconds: 15),
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _token =
           tokenEndpoint ?? Uri.parse('https://oauth2.googleapis.com/token'),
       _revoke =
           revokeEndpoint ?? Uri.parse('https://oauth2.googleapis.com/revoke'),
       _now = clock ?? DateTime.now;

  /// Time limit per request.
  final Duration timeout;

  final http.Client _client;
  final Uri _token;
  final Uri _revoke;
  final DateTime Function() _now;

  @override
  Future<GoogleTokenSet> exchangeCode({
    required GoogleClient client,
    required String code,
    required String verifier,
    required Uri redirect,
  }) async {
    final set = await _tokenRequest({
      'grant_type': 'authorization_code',
      'client_id': client.id,
      'client_secret': client.secret,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirect.toString(),
    });
    if (set.refreshToken == null) {
      throw const PortException(
        PortErrorKind.rejected,
        'Google hat kein Refresh-Token geschickt. Bitte den Zugriff von '
        'Wendelin unter myaccount.google.com/permissions entfernen und neu '
        'anmelden.',
      );
    }
    return set;
  }

  @override
  Future<GoogleTokenSet> refresh(GoogleClient client, String refreshToken) =>
      _tokenRequest({
        'grant_type': 'refresh_token',
        'client_id': client.id,
        'client_secret': client.secret,
        'refresh_token': refreshToken,
      });

  @override
  Future<void> revoke(String token) async {
    try {
      await _client.post(_revoke, body: {'token': token}).timeout(timeout);
    } on Object {
      // Best effort: the local login is deleted anyway.
    }
  }

  Future<GoogleTokenSet> _tokenRequest(Map<String, String> form) async {
    final http.Response response;
    try {
      response = await _client.post(_token, body: form).timeout(timeout);
    } on TimeoutException {
      throw const PortException(
        PortErrorKind.unavailable,
        'Google antwortet nicht (Zeitüberschreitung)',
      );
    } on http.ClientException {
      throw _unreachable;
    } on IOException {
      throw _unreachable;
    }
    final status = response.statusCode;
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    final map = json is Map<String, Object?> ? json : null;
    if (status >= 500) {
      throw PortException(
        PortErrorKind.unavailable,
        'Google hat einen Serverfehler (HTTP $status)',
      );
    }
    if (status == 429) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Google: Anfragelimit erreicht, später erneut versuchen',
      );
    }
    if (status == 400 || status == 401) {
      final code = map?['error'];
      final safe = code is String && RegExp(r'^[a-z_]{1,40}$').hasMatch(code)
          ? code
          : 'unbekannt';
      throw PortException(PortErrorKind.permissionDenied, switch (safe) {
        'invalid_client' || 'unauthorized_client' =>
          'Google lehnt Client-ID oder Client-Secret ab ($safe)',
        'invalid_grant' =>
          'Google hat die Anmeldung abgelehnt oder widerrufen '
              '(invalid_grant)',
        _ => 'Google hat die Anmeldung abgelehnt ($safe)',
      });
    }
    final access = map?['access_token'];
    final expires = map?['expires_in'];
    if (status != 200 ||
        map == null ||
        access is! String ||
        access.isEmpty ||
        expires is! int) {
      throw const PortException(
        PortErrorKind.failed,
        'Google: unerwartete Antwort (Format geändert?)',
      );
    }
    final scope = map['scope'];
    if (scope is String && !scope.split(' ').contains(googleTasksScope)) {
      throw const PortException(
        PortErrorKind.rejected,
        'Google hat den Zugriff auf Aufgaben nicht erteilt. Bitte bei der '
        'Anmeldung „Aufgaben ansehen und verwalten“ erlauben.',
      );
    }
    final refresh = map['refresh_token'];
    return GoogleTokenSet(
      GoogleAccessToken(access, _now().add(Duration(seconds: expires))),
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
    );
  }

  static const _unreachable = PortException(
    PortErrorKind.unavailable,
    'Google ist nicht erreichbar',
  );
}
