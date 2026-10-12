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
  });

  /// Sessions in the database.
  final ConversationRepository conversations;

  /// Time source.
  final Clock clock;

  /// Called with the id of every session that ended.
  final void Function(String sessionId) onSessionEnd;

  /// Inactivity after which a session ends.
  final Duration inactivity;

  String? _current;
  Timer? _timer;

  /// Id of the current session, if one is open.
  String? get currentId => _current;

  /// The session for a new request: the open one, or a new one if the last
  /// one ended. Restarts the inactivity timer.
  Future<String> ensure() async {
    final session = await conversations.currentOrNew(
      clock.now(),
      inactivity: inactivity,
    );
    _switchTo(session.id);
    touch();
    return session.id;
  }

  /// Starts a new session („neues Thema“).
  Future<String> startNew() async {
    final session = await conversations.startNew(clock.now());
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
