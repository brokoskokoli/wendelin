import '../common/file_queue.dart';
import '../common/matching.dart';
import '../common/port_exception.dart';
import 'bring_api.dart';

/// Hint appended to errors that pause the integration.
const bringFallbackHint =
    'Bring!-Tools sind pausiert. Ausweg: Artikel über „Teilen“ an die '
    'Bring!-App schicken.';

/// Hint appended to temporary errors (offline, timeout, 429, 5xx); the
/// integration stays active.
const bringRetryHint =
    'Bitte später erneut versuchen. Ausweg: Artikel über „Teilen“ an die '
    'Bring!-App schicken.';

/// Login handling and error state of the Bring! tools.
///
/// Every API call runs through [run]: the session is taken from memory,
/// then from [BringSecrets], else a login with the stored credentials
/// starts. A rejected token (`permissionDenied`) is renewed **once** (refresh
/// token, then a new login) and the call repeated once; HTTP 401 means the
/// call was not applied, so this is safe for writes too. Nothing else is
/// repeated. Lasting failures (login or token still rejected after the
/// renewal, unexpected answers: HTML, missing fields, unknown status) call
/// [onError] (the app: `ToolRegistry.reportError`, tools paused) and are
/// rethrown with [bringFallbackHint]. Temporary ones (`unavailable`:
/// offline, timeout, 429, 5xx) only fail the call, with [bringRetryHint].
final class BringSession {
  /// Creates the session.
  BringSession(this.api, this.secrets, {this.onError, this.onRecovered});

  /// The API client.
  final BringApi api;

  /// Where credentials and tokens live.
  final BringSecrets secrets;

  /// Called with a German message when the integration must show „Fehler“.
  final void Function(String message)? onError;

  /// Called when a call succeeds after [onError].
  final void Function()? onRecovered;

  BringAuth? _auth;
  Future<BringAuth>? _renewing;
  bool _failed = false;

  /// Whether the last failure put the integration into the error state and
  /// no call has succeeded since.
  bool get failed => _failed;

  /// Error when no credentials are stored (setup, not a failure).
  static const notSetUp = PortException(
    PortErrorKind.permissionDenied,
    'Bring! ist nicht eingerichtet (Einstellungen → Integrationen → Bring!).',
  );

  /// Runs [op] with a valid session (see the class comment).
  Future<T> run<T>(Future<T> Function(BringAuth auth) op) async {
    try {
      final auth = await _current();
      T result;
      try {
        result = await op(auth);
      } on PortException catch (e) {
        if (e.kind != PortErrorKind.permissionDenied) rethrow;
        result = await op(await _renew(auth));
      }
      if (_failed) {
        _failed = false;
        onRecovered?.call();
      }
      return result;
    } on PortException catch (e) {
      if (identical(e, notSetUp) || e.kind == PortErrorKind.notFound) {
        rethrow;
      }
      if (e.kind == PortErrorKind.unavailable) {
        throw PortException(e.kind, '${e.message}. $bringRetryHint');
      }
      if (e.kind == PortErrorKind.permissionDenied) await _drop();
      _failed = true;
      onError?.call(e.message);
      throw PortException(e.kind, '${e.message}. $bringFallbackHint');
    }
  }

  /// Runs [body] exclusively for the list [listUuid] (read-check-write of
  /// parallel calls and undos never interleave).
  Future<T> exclusive<T>(String listUuid, Future<T> Function() body) =>
      FileQueue.run('bring:$listUuid', body);

  /// Forgets the session in memory and in [secrets] (e.g. after the login
  /// changed in the settings).
  Future<void> forget() => _drop();

  Future<void> _drop() async {
    _auth = null;
    await secrets.saveAuth(null);
  }

  Future<BringAuth> _current() async {
    final cached = _auth ??= await secrets.auth();
    if (cached != null) return cached;
    return _renew(null);
  }

  /// A new session replacing [stale]; parallel callers share one renewal.
  Future<BringAuth> _renew(BringAuth? stale) {
    final current = _auth;
    if (current != null && current != stale) return Future.value(current);
    return _renewing ??= _doRenew(stale).whenComplete(() => _renewing = null);
  }

  Future<BringAuth> _doRenew(BringAuth? stale) async {
    BringAuth? fresh;
    if (stale != null && stale.refreshToken != null) {
      try {
        fresh = await api.refresh(stale);
      } on PortException catch (e) {
        if (e.kind != PortErrorKind.permissionDenied) rethrow;
      }
    }
    if (fresh == null) {
      final login = await secrets.credentials();
      if (login == null) throw notSetUp;
      fresh = await api.login(login.email, login.password);
    }
    _auth = fresh;
    await secrets.saveAuth(fresh);
    return fresh;
  }

  /// The lists of the account plus the account's default list id.
  Future<({List<BringList> lists, String? defaultUuid})> lists() =>
      run((auth) async {
        final lists = await api.lists(auth);
        return (lists: lists, defaultUuid: auth.defaultListUuid);
      });

  /// The list [query] names (fuzzy, like the lists integration), or the
  /// default list for `null`/blank or a generic name („Bring-Liste“,
  /// „Einkaufsliste“) that matches no list. With [write], a whole-word match
  /// only is asked back. Throws `PortException(notFound|rejected)`.
  Future<BringList> resolveList(String? query, {required bool write}) async {
    final (:lists, :defaultUuid) = await this.lists();
    if (lists.isEmpty) {
      throw const PortException(
        PortErrorKind.notFound,
        'Im Bring!-Konto gibt es keine Listen.',
      );
    }
    final names = lists.map((l) => l.name).join(', ');
    if (query == null || query.isEmpty) return _default(lists, defaultUuid);
    final m = bestMatches(query, lists, (l) => [l.name]);
    if (m.best.isEmpty) {
      if (_generic.contains(foldText(query).replaceAll(' ', ''))) {
        return _default(lists, defaultUuid);
      }
      throw PortException(
        PortErrorKind.notFound,
        'Keine Bring!-Liste „$query“. Vorhanden: $names',
      );
    }
    if (m.best.length > 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Mehrdeutig: „$query“ passt zu '
        '${m.best.map((l) => l.name).join(', ')}. Bitte nachfragen, welche '
        'Bring!-Liste gemeint ist.',
      );
    }
    if (write && m.score == 1) {
      throw PortException(
        PortErrorKind.rejected,
        'Meintest du die Bring!-Liste „${m.best.single.name}“? Bitte '
        'nachfragen.',
      );
    }
    return m.best.single;
  }

  BringList _default(List<BringList> lists, String? defaultUuid) {
    for (final l in lists) {
      if (l.uuid == defaultUuid) return l;
    }
    if (lists.length == 1) return lists.single;
    throw PortException(
      PortErrorKind.rejected,
      'Welche Bring!-Liste? Vorhanden: ${lists.map((l) => l.name).join(', ')}. '
      'Bitte nachfragen.',
    );
  }

  /// Names (folded, without spaces) that mean „the Bring! list“ in general.
  static const _generic = {
    'bring',
    'bringliste',
    'bringlist',
    'bringeinkaufsliste',
    'einkaufsliste',
    'einkaufen',
    'einkauf',
    'shopping',
    'shoppinglist',
    'grocerylist',
    'groceries',
    'listedecourses',
    'courses',
    'standard',
    'default',
  };
}
