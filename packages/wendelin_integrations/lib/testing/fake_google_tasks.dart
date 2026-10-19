import 'dart:async';

import '../src/common/port_exception.dart';
import '../src/google_tasks/google_oauth.dart';
import '../src/google_tasks/google_tasks_api.dart';
import '../src/google_tasks/google_tasks_login.dart';

/// In-memory [GoogleTasksApi], [GoogleOAuthApi] and [GoogleTasksSecrets] for
/// tests and the demo mode.
///
/// Knows the lists „Meine Aufgaben“ (default) and „Arbeit“. Only the access
/// token [validAccess] is accepted by the API; the fake OAuth hands it out
/// for [validRefresh]. [failWith] makes all task calls fail while it is set.
final class FakeGoogleTasksApi
    implements GoogleTasksApi, GoogleOAuthApi, GoogleTasksSecrets {
  /// Creates the fake with [listRows] and open [tasks].
  FakeGoogleTasksApi({
    List<GoogleTaskList>? listRows,
    List<GoogleTask> tasks = const [],
    this.storedClient = const GoogleClient(
      id: 'fake.apps.googleusercontent.com',
      secret: 'fake-secret',
    ),
    this.storedRefresh = validRefresh,
  }) : listRows =
           listRows ??
           const [
             GoogleTaskList(id: 'l-default', title: 'Meine Aufgaben'),
             GoogleTaskList(id: 'l-work', title: 'Arbeit'),
           ],
       open = [...tasks];

  /// Access token the task calls accept.
  static const validAccess = 'fake-google-access';

  /// Refresh token the fake OAuth accepts.
  static const validRefresh = 'fake-google-refresh';

  /// Stored client (`null` = not set up).
  GoogleClient? storedClient;

  /// Stored refresh token (`null` = not logged in).
  String? storedRefresh;

  /// Lists.
  final List<GoogleTaskList> listRows;

  /// Open tasks.
  final List<GoogleTask> open;

  /// Completed tasks (kept for reopening).
  final Map<String, GoogleTask> done = {};

  /// Error thrown by every task call, if set.
  PortException? failWith;

  /// Error thrown by [refresh], if set.
  PortException? refreshFailWith;

  /// When set, task calls reject this many calls with 401 first.
  int rejectNext = 0;

  /// Operations called, in order (no arguments).
  final List<String> calls = [];

  /// Revoked tokens, in order.
  final List<String> revoked = [];

  /// The clock the fake OAuth uses for expiry.
  DateTime Function() now = DateTime.now;

  /// Lifetime of handed-out access tokens.
  Duration lifetime = const Duration(hours: 1);

  int _next = 1;

  @override
  Future<GoogleClient?> client() async => storedClient;

  @override
  Future<void> saveClient(GoogleClient? client) async => storedClient = client;

  @override
  Future<String?> refreshToken() async => storedRefresh;

  @override
  Future<void> saveRefreshToken(String? token) async => storedRefresh = token;

  @override
  Future<GoogleTokenSet> exchangeCode({
    required GoogleClient client,
    required String code,
    required String verifier,
    required Uri redirect,
  }) async {
    calls.add('exchange');
    if (code != 'fake-code') {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Google hat die Anmeldung abgelehnt (invalid_grant)',
      );
    }
    return GoogleTokenSet(
      GoogleAccessToken(validAccess, now().add(lifetime)),
      refreshToken: validRefresh,
    );
  }

  @override
  Future<GoogleTokenSet> refresh(GoogleClient client, String token) async {
    calls.add('refresh');
    final f = refreshFailWith;
    if (f != null) throw f;
    if (token != validRefresh) {
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Google hat die Anmeldung abgelehnt oder widerrufen (invalid_grant)',
      );
    }
    return GoogleTokenSet(GoogleAccessToken(validAccess, now().add(lifetime)));
  }

  @override
  Future<void> revoke(String token) async => revoked.add(token);

  void _check(String token, String op) {
    calls.add(op);
    final f = failWith;
    if (f != null) throw f;
    if (rejectNext > 0 || token != validAccess) {
      if (rejectNext > 0) rejectNext--;
      throw const PortException(
        PortErrorKind.permissionDenied,
        'Google Tasks-Zugang abgelehnt: Anmeldung abgelaufen (HTTP 401)',
      );
    }
  }

  PortException get _gone => const PortException(
    PortErrorKind.notFound,
    'Google Tasks: Aufgabe nicht gefunden',
  );

  @override
  Future<List<GoogleTaskList>> taskLists(String accessToken) async {
    _check(accessToken, 'lists');
    return [...listRows];
  }

  @override
  Future<List<GoogleTask>> tasks(String accessToken, String listId) async {
    _check(accessToken, 'tasks');
    return [
      for (final t in open)
        if (t.listId == listId) t,
    ];
  }

  @override
  Future<GoogleTask> addTask(
    String accessToken,
    String listId, {
    required String title,
    String? due,
  }) async {
    _check(accessToken, 'add');
    final task = GoogleTask(
      id: 't-${_next++}',
      listId: listId,
      title: title,
      due: due,
    );
    open.add(task);
    return task;
  }

  @override
  Future<void> setCompleted(
    String accessToken,
    String listId,
    String taskId, {
    required bool completed,
  }) async {
    _check(accessToken, completed ? 'complete' : 'reopen');
    if (completed) {
      final i = open.indexWhere((t) => t.id == taskId && t.listId == listId);
      if (i < 0) throw _gone;
      done[taskId] = open.removeAt(i);
    } else {
      final t = done.remove(taskId);
      if (t == null) throw _gone;
      open.add(t);
    }
  }

  @override
  Future<void> deleteTask(
    String accessToken,
    String listId,
    String taskId,
  ) async {
    _check(accessToken, 'delete');
    final before = open.length;
    open.removeWhere((t) => t.id == taskId && t.listId == listId);
    if (open.length == before) throw _gone;
  }
}

/// A [GoogleBrowserOpener] that records the address and lets a test react.
final class FakeGoogleBrowser implements GoogleBrowserOpener {
  /// Creates the fake; [onOpen] runs with the login address.
  FakeGoogleBrowser([this.onOpen]);

  /// Reaction to the login page being opened (e.g. call the redirect).
  Future<void> Function(Uri url)? onOpen;

  /// Whether a browser exists.
  bool available = true;

  /// Addresses opened, in order.
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    if (!available) return false;
    opened.add(url);
    final f = onOpen;
    if (f != null) await f(url);
    return true;
  }
}

/// A [RedirectReceiver] without a socket: a test (usually from
/// [FakeGoogleBrowser.onOpen]) calls [deliver] with the redirect query.
final class FakeRedirectReceiver implements RedirectReceiver {
  final _answer = Completer<Uri>();
  bool Function(Map<String, String> query)? _accept;

  @override
  final Uri redirect = Uri.parse('http://127.0.0.1:4711/oauth2/callback');

  /// Completes [wait] with the redirect plus [query]; like the real server a
  /// query the wait refuses (wrong `state`) is ignored.
  void deliver(Map<String, String> query) {
    final accept = _accept;
    // Like the real server: nothing is accepted before wait() names the rule.
    if (accept == null || !accept(query)) return;
    if (!_answer.isCompleted) {
      _answer.complete(redirect.replace(queryParameters: query));
    }
  }

  @override
  Future<Uri> wait(
    Duration timeout, {
    bool Function(Map<String, String> query)? accept,
  }) {
    _accept = accept;
    return _answer.future;
  }

  /// Whether [close] was called.
  bool closed = false;

  @override
  Future<void> close() async {
    closed = true;
    if (!_answer.isCompleted) {
      _answer.completeError(StateError('Anmeldung abgebrochen'));
      unawaited(_answer.future.then<void>((_) {}, onError: (Object _) {}));
    }
  }
}
