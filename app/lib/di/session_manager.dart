import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Persists the time the window left the screen, so an app kill in the
/// background does not hide how long the user was away (WP157 part B).
abstract interface class AbsenceStamp {
  /// The stored time, or `null`. Throws if the entry is unreadable.
  Future<DateTime?> load();

  /// Stores [at]; `null` removes the entry.
  Future<void> save(DateTime? at);
}

/// Keeps track of the current conversation session (concept: a session
/// ends after 5 min of inactivity or on „neues Thema“).
///
/// When a session ends, [onSessionEnd] runs once with its id (the app then
/// forgets unlocked tools and cached calendar data). The inactivity timer
/// ends the session proactively, so caches do not outlive it.
final class SessionManager {
  /// Creates the manager.
  SessionManager({
    required this.conversations,
    required this.clock,
    required this.onSessionEnd,
    this.inactivity = ConversationRepository.defaultInactivity,
    this.origin = SessionOrigin.app,
    this.absence,
    this.absenceLimit = const Duration(minutes: 1),
  });

  /// Where the time of leaving the screen is kept across an app kill
  /// (`null`: the overlay, which always starts fresh anyway).
  final AbsenceStamp? absence;

  /// Time out of sight after which the session ends (WP157 part B).
  final Duration absenceLimit;

  /// Sessions in the database.
  final ConversationRepository conversations;

  /// Time source.
  final Clock clock;

  /// Called with the id of every session that ended.
  final void Function(String sessionId) onSessionEnd;

  /// Inactivity after which a session ends.
  final Duration inactivity;

  /// Engine this manager belongs to; it only picks up and starts sessions of
  /// this origin, so the overlay never leaks into the app chat (WP67).
  final SessionOrigin origin;

  String? _current;
  Timer? _timer;
  bool _fresh = false;
  DateTime? _leftAt;
  Timer? _absenceTimer;

  Future<Session> _currentOrNew() => conversations.currentOrNew(
    clock.now(),
    inactivity: inactivity,
    origin: origin,
  );

  // This manager's own session while it is still active: another engine
  // (overlay) may have opened a newer one in the shared database, which
  // must not take over this conversation (WP67).
  Future<Session?> _own() async {
    final id = _current;
    if (id == null) return null;
    final own = await conversations.session(id);
    if (own == null ||
        clock.now().difference(own.lastActivityAt) >= inactivity) {
      return null;
    }
    return own;
  }

  /// The next request starts a new session, whatever the database holds
  /// (every assistant overlay invocation starts a fresh conversation, WP67).
  /// Ends the current session now.
  void beginFresh() {
    end();
    _fresh = true;
  }

  /// Id of the current session, if one is open.
  String? get currentId => _current;

  /// The session for a new request: the open one, or a new one if the last
  /// one ended. Restarts the inactivity timer.
  Future<String> ensure() async {
    final Session session;
    if (_fresh) {
      _fresh = false;
      session = await conversations.startNew(clock.now(), origin: origin);
    } else {
      session = await _own() ?? await _currentOrNew();
    }
    _switchTo(session.id);
    touch();
    return session.id;
  }

  /// Starts a new session („neues Thema“).
  Future<String> startNew() async {
    final session = await conversations.startNew(clock.now(), origin: origin);
    _switchTo(session.id);
    touch();
    return session.id;
  }

  /// Marks activity now (restarts the inactivity timer).
  void touch() {
    _timer?.cancel();
    if (_current == null) return;
    _timer = Timer(inactivity, end);
  }

  /// Ends the current session, if any.
  void end() {
    _timer?.cancel();
    _timer = null;
    final id = _current;
    _current = null;
    if (id != null) onSessionEnd(id);
  }

  /// The window left the screen (hidden/paused): remembers when (also
  /// persisted, an app kill must not forget it) and ends the session after
  /// [absenceLimit] even if the process is still alive. Repeated calls keep
  /// the first time. Cannot persist: ends the session now (fail-closed).
  void leftScreen() {
    if (_leftAt != null) return;
    final at = clock.now();
    _leftAt = at;
    _absenceTimer?.cancel();
    _absenceTimer = Timer(absenceLimit, end);
    final store = absence;
    if (store == null) return;
    unawaited(
      store.save(at).catchError((Object _) {
        beginFresh();
      }),
    );
  }

  /// The window is visible again (or the app starts). Returns `true` if it
  /// was out of sight for [absenceLimit] or longer: the session has ended
  /// and the next request starts a new one. An unreadable or future time
  /// counts as expired (fail-closed).
  Future<bool> returnedToScreen() async {
    _absenceTimer?.cancel();
    _absenceTimer = null;
    var left = _leftAt;
    _leftAt = null;
    var expired = false;
    final store = absence;
    if (store != null) {
      if (left == null) {
        try {
          left = await store.load();
        } on Object {
          expired = true;
        }
      }
      try {
        await store.save(null);
      } on Object {
        // A stale entry only ends a later session early.
      }
    }
    if (left != null) {
      final away = clock.now().difference(left);
      expired = expired || away.isNegative || away >= absenceLimit;
    }
    if (expired) beginFresh();
    return expired;
  }

  /// Stops the timer without ending the session (app shutdown).
  void dispose() {
    _absenceTimer?.cancel();
    _timer?.cancel();
    _timer = null;
  }

  void _switchTo(String id) {
    final previous = _current;
    if (previous == id) return;
    _current = id;
    if (previous != null) onSessionEnd(previous);
  }
}
