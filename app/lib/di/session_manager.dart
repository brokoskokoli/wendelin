import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

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
  });

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

  /// Stops the timer without ending the session (app shutdown).
  void dispose() {
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
