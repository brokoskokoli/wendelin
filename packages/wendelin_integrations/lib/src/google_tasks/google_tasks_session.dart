import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../common/matching.dart';
import '../common/port_exception.dart';
import 'google_oauth.dart';
import 'google_tasks_api.dart';

/// Hint appended to errors that pause the integration.
const googleTasksPausedHint =
    'Google-Tasks-Tools sind pausiert. Bitte unter Einstellungen → '
    'Integrationen → Google Tasks neu anmelden.';

/// Hint appended to temporary errors (offline, timeout, 429, 5xx).
const googleTasksRetryHint = 'Bitte später erneut versuchen.';

/// Token handling and error state of the Google Tasks tools.
///
/// Every API call runs through [run]: the access token lives in memory only
/// and is renewed from the stored refresh token when missing or expired,
/// and **once** after a rejected call (HTTP 401; the call was not applied,
/// so repeating it is safe). When Google refuses the renewal (login
/// revoked; in the „Testing“ mode of a Cloud project refresh tokens end
/// after 7 days) the refresh token is deleted and [onError] pauses the
/// integration. Any other lasting failure pauses it but keeps the login.
/// Temporary failures only fail the call. Messages never contain tokens.
final class GoogleTasksSession {
  /// Creates the session.
  GoogleTasksSession(
    this.api,
    this.oauth,
    this.secrets, {
    this.onError,
    this.onRecovered,
    this._clock = const SystemClock(),
  });

  /// The Tasks API.
  final GoogleTasksApi api;

  /// The token endpoint.
  final GoogleOAuthApi oauth;

  /// Client and refresh token.
  final GoogleTasksSecrets secrets;

  /// Called with a German message when the integration must show „Fehler“.
  final void Function(String message)? onError;

  /// Called when a call succeeds after [onError].
  final void Function()? onRecovered;

  final Clock _clock;
  GoogleAccessToken? _access;
  Future<GoogleAccessToken>? _renewing;
  bool _failed = false;

  /// Whether the last failure paused the integration and no call has
  /// succeeded since.
  bool get failed => _failed;

  /// Error when nothing is set up (not a failure).
  static const notSetUp = PortException(
    PortErrorKind.permissionDenied,
    'Google Tasks ist nicht eingerichtet (Einstellungen → Integrationen → '
    'Google Tasks).',
  );

  /// Forgets the cached access token (after sign-out or a new login).
  void reset() {
    _access = null;
    _renewing = null;
  }

  /// Runs [op] with a valid access token (see the class comment).
  Future<T> run<T>(Future<T> Function(String accessToken) op) async {
    var refreshRejected = false;
    Future<GoogleAccessToken> renew() async {
      try {
        return await (_renewing ??= _renew().whenComplete(
          () => _renewing = null,
        ));
      } on PortException catch (e) {
        if (e.kind == PortErrorKind.permissionDenied) refreshRejected = true;
        rethrow;
      }
    }

    try {
      var access = _access;
      if (access == null || !access.validAt(_clock.now())) {
        access = await renew();
      }
      T result;
      try {
        result = await op(access.token);
      } on PortException catch (e) {
        if (e.kind != PortErrorKind.permissionDenied) rethrow;
        result = await op((await renew()).token);
      }
      if (_failed) {
        _failed = false;
        onRecovered?.call();
      }
      return result;
    } on PortException catch (e) {
      if (identical(e, notSetUp)) rethrow;
      switch (e.kind) {
        case PortErrorKind.unavailable:
          throw PortException(e.kind, '${e.message}. $googleTasksRetryHint');
        case PortErrorKind.permissionDenied || PortErrorKind.failed:
          if (refreshRejected) {
            await secrets.saveRefreshToken(null);
            reset();
          }
          _failed = true;
          final msg = refreshRejected
              ? 'Google-Anmeldung abgelaufen oder widerrufen (im '
                    'Testnutzer-Modus endet sie nach 7 Tagen)'
              : e.message;
          onError?.call(msg);
          throw PortException(e.kind, '$msg. $googleTasksPausedHint');
        default:
          rethrow;
      }
    }
  }

  Future<GoogleAccessToken> _renew() async {
    final client = await secrets.client();
    final refresh = await secrets.refreshToken();
    if (client == null || refresh == null || refresh.isEmpty) {
      throw notSetUp;
    }
    final set = await oauth.refresh(client, refresh);
    final rotated = set.refreshToken;
    if (rotated != null && rotated != refresh) {
      await secrets.saveRefreshToken(rotated);
    }
    return _access = set.access;
  }

  /// Task lists of the account.
  Future<List<GoogleTaskList>> lists() => run(api.taskLists);

  /// The list [query] names (fuzzy, like the lists integration), or the
  /// account's first (default) list for `null`/blank. With [write], a
  /// whole-word match only is asked back. Throws
  /// `PortException(notFound|rejected)`.
  Future<GoogleTaskList> resolveList(
    String? query, {
    required bool write,
  }) async {
    final all = await lists();
    if (all.isEmpty) {
      throw const PortException(
        PortErrorKind.notFound,
        'Im Google-Konto gibt es keine Aufgabenlisten.',
      );
    }
    final names = all.map((l) => l.title).join(', ');
    if (query == null || query.trim().isEmpty) return all.first;
    final m = bestMatches(query, all, (l) => [l.title]);
    if (m.best.isEmpty) {
      throw PortException(
        PortErrorKind.notFound,
        'Keine Google-Aufgabenliste „$query“. Vorhanden: $names',
      );
    }
    if (m.best.length > 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Mehrdeutig: „$query“ passt zu '
        '${m.best.map((l) => l.title).join(', ')}. Bitte nachfragen, welche '
        'Liste gemeint ist.',
      );
    }
    if (write && m.score == 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Meintest du die Google-Liste „${m.best.single.title}“? Bitte '
        'nachfragen.',
      );
    }
    return m.best.single;
  }
}
