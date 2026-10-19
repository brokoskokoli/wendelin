import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../common/pkce.dart';
import '../common/port_exception.dart';
import 'google_oauth.dart';

/// Opens the login page in the browser (app: Custom Tab or any browser).
abstract interface class GoogleBrowserOpener {
  /// Opens [url]; `false` if no browser can show it.
  Future<bool> open(Uri url);
}

/// Path of the loopback redirect.
const googleLoopbackPath = '/oauth2/callback';

/// Where the login redirect arrives (a local server; tests use a fake).
abstract interface class RedirectReceiver {
  /// The redirect address for the login.
  Uri get redirect;

  /// The first redirect request for which [accept] is true, as a full
  /// address; other requests on the path get 400 and the wait goes on (so
  /// foreign local requests cannot end the login). Fails with
  /// [TimeoutException] after [timeout] and with [StateError] after [close].
  Future<Uri> wait(
    Duration timeout, {
    bool Function(Map<String, String> query)? accept,
  });

  /// Stops the receiver; a pending [wait] fails with [StateError].
  Future<void> close();
}

/// The login redirect arrives on a local HTTP server (Google allows no
/// custom scheme for installed apps without Play services; the user's
/// „Desktop“ OAuth client accepts `http://127.0.0.1:<any port>`).
///
/// Bound to the IPv4 loopback address only (never reachable from the
/// network), on a random port. Takes **one** accepted request on
/// [googleLoopbackPath] with the right host header; anything else gets 404,
/// a request the `accept` predicate refuses (wrong or missing `state`) gets
/// 400 and the server keeps waiting. Closes itself after the accepted
/// request, on timeout and on [close].
final class LoopbackReceiver implements RedirectReceiver {
  LoopbackReceiver._(this._server)
    : _port = _server.port,
      address = _server.address {
    _server.listen(_handle, onError: (Object _) {}, cancelOnError: false);
  }

  /// Starts a server on a free port.
  static Future<LoopbackReceiver> start() async => LoopbackReceiver._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  final HttpServer _server;

  /// The address the server is bound to (always IPv4 loopback).
  final InternetAddress address;
  final int _port;
  final _done = Completer<Uri>();
  bool Function(Map<String, String> query)? _accept;

  @override
  Uri get redirect => Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: _port,
    path: googleLoopbackPath,
  );

  /// The first request on the redirect path. The server is closed
  /// afterwards in every case.
  @override
  Future<Uri> wait(
    Duration timeout, {
    bool Function(Map<String, String> query)? accept,
  }) {
    _accept = accept ?? (_) => true;
    return _done.future.timeout(timeout).whenComplete(close);
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) {
      _done.completeError(StateError('Anmeldung abgebrochen'));
      // Nobody may be waiting yet: do not report an unhandled error.
      unawaited(_done.future.then<void>((_) {}, onError: (Object _) {}));
    }
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final ok =
        !_done.isCompleted &&
        request.method == 'GET' &&
        request.uri.path == googleLoopbackPath &&
        request.headers.host == '127.0.0.1' &&
        request.headers.port == _port;
    if (!ok) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final accept = _accept;
    // Nothing is accepted before wait() names the rule.
    if (accept == null || !accept(request.uri.queryParameters)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final uri = redirect.replace(query: request.uri.query);
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_page);
    await request.response.close();
    if (!_done.isCompleted) _done.complete(uri);
    unawaited(_server.close());
  }

  static const _page =
      '<!doctype html><html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>Wendelin</title></head><body style="font-family:sans-serif;'
      'margin:2em"><h1>Done / Fertig / Terminé</h1><p>You can close this window and '
      'return to Wendelin.</p></body></html>';
}

/// Whether [id] looks like a Google OAuth client ID.
bool isGoogleClientId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\.apps\.googleusercontent\.com$')
        .hasMatch(id);

/// Why [GoogleTasksLogin.signIn] failed; the UI shows a text per kind. Never
/// carries a secret.
enum GoogleLoginError {
  /// The client ID does not look like a Google OAuth client ID.
  invalidClientId,

  /// The client secret is empty or has blanks.
  missingSecret,

  /// No browser can show the login page.
  noBrowser,

  /// No answer from Google in time.
  timeout,

  /// The login was cancelled (cancel button, screen left).
  cancelled,

  /// The user or Google denied access (test user missing?).
  accessDenied,

  /// Google refused the login with another error.
  denied,

  /// The answer holds no code.
  noCode,

  /// The local receiver could not be started.
  receiverUnavailable,

  /// Google rejects the client ID or secret.
  clientRejected,

  /// Google sent no refresh token.
  noRefreshToken,

  /// Google is not reachable.
  unavailable,

  /// Any other failure.
  failed,
}

/// Login with the user's own Google Cloud OAuth client (Authorization Code
/// with PKCE S256 and a loopback redirect).
final class GoogleTasksLogin {
  /// Creates the login; [random] must be `Random.secure()` outside tests.
  GoogleTasksLogin(
    this.oauth,
    this.secrets,
    this.browser, {
    Random? random,
    this.timeout = const Duration(minutes: 5),
    Future<RedirectReceiver> Function()? receiver,
  }) : _random = random ?? Random.secure(),
       _receiver = receiver ?? LoopbackReceiver.start;

  /// The token endpoint.
  final GoogleOAuthApi oauth;

  /// Where client and refresh token are stored.
  final GoogleTasksSecrets secrets;

  /// Shows the login page.
  final GoogleBrowserOpener browser;

  /// How long to wait for the user in the browser.
  final Duration timeout;

  final Random _random;
  final Future<RedirectReceiver> Function() _receiver;
  RedirectReceiver? _active;
  bool _cancelRequested = false;

  /// The login address (exposed for tests).
  Uri authorizationUrl(
    String clientId,
    Uri redirect,
    String state,
    String verifier,
  ) => googleAuthorizationEndpoint.replace(
    queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirect.toString(),
      'scope': googleTasksScope,
      'state': state,
      'code_challenge_method': 'S256',
      'code_challenge': pkceChallenge(verifier),
      // A refresh token is only sent with consent.
      'access_type': 'offline',
      'prompt': 'consent',
    },
  );

  /// Stops a running login (it ends with „abgebrochen“).
  Future<void> cancel() async {
    _cancelRequested = true;
    await _active?.close();
  }

  /// Logs in with the user's client. Returns `null` on success (client and
  /// refresh token are stored then), else the reason; nothing is stored on a
  /// failure.
  Future<GoogleLoginError?> signIn(String clientId, String clientSecret) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (!isGoogleClientId(id)) return GoogleLoginError.invalidClientId;
    if (secret.isEmpty || secret.contains(RegExp(r'\s'))) {
      return GoogleLoginError.missingSecret;
    }
    final verifier = randomUnreserved(_random, 64);
    final state = randomUnreserved(_random, 32);
    RedirectReceiver? receiver;
    _cancelRequested = false;
    try {
      receiver = _active = await _receiver();
      // cancel() during the start of the receiver found no `_active` yet.
      if (_cancelRequested) return GoogleLoginError.cancelled;
      // Listening starts before the browser opens, so no early answer is
      // refused; an unused answer must not end in an unhandled error.
      final answer = receiver.wait(
        timeout,
        accept: (query) => query['state'] == state,
      );
      unawaited(answer.then<void>((_) {}, onError: (Object _) {}));
      final opened = await browser.open(
        authorizationUrl(id, receiver.redirect, state, verifier),
      );
      if (!opened) return GoogleLoginError.noBrowser;
      final Uri back;
      try {
        back = await answer;
      } on TimeoutException {
        return GoogleLoginError.timeout;
      } on StateError {
        return GoogleLoginError.cancelled;
      }
      final params = back.queryParameters;
      // The receiver only hands over answers with the right `state`.
      final error = params['error'];
      if (error != null) {
        return error == 'access_denied'
            ? GoogleLoginError.accessDenied
            : GoogleLoginError.denied;
      }
      final code = params['code'];
      if (code == null || code.isEmpty) return GoogleLoginError.noCode;
      final client = GoogleClient(id: id, secret: secret);
      final tokens = await oauth.exchangeCode(
        client: client,
        code: code,
        verifier: verifier,
        redirect: receiver.redirect,
      );
      await secrets.saveClient(client);
      await secrets.saveRefreshToken(tokens.refreshToken);
      return null;
    } on PortException catch (e) {
      return switch (e.kind) {
        PortErrorKind.permissionDenied => GoogleLoginError.clientRejected,
        PortErrorKind.rejected => GoogleLoginError.noRefreshToken,
        PortErrorKind.unavailable => GoogleLoginError.unavailable,
        _ => GoogleLoginError.failed,
      };
    } on SocketException {
      return GoogleLoginError.receiverUnavailable;
    } finally {
      _active = null;
      await receiver?.close();
    }
  }

  /// Revokes the refresh token at Google (best effort) and deletes client,
  /// secret and token.
  Future<void> signOut() async {
    final token = await secrets.refreshToken();
    if (token != null && token.isNotEmpty) {
      try {
        await oauth.revoke(token);
      } on Object {
        // Best effort.
      }
    }
    await secrets.saveRefreshToken(null);
    await secrets.saveClient(null);
  }
}
