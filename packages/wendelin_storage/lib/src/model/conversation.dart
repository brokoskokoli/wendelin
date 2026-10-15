import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Which engine opened a session. The app chat and the assistant overlay
/// keep separate sessions (WP67).
enum SessionOrigin {
  /// The main app.
  app,

  /// The assistant overlay.
  overlay,
}

/// A conversation session (ends after inactivity or on "neues Thema").
@immutable
final class Session {
  /// Creates a session.
  const Session({
    required this.id,
    required this.startedAt,
    required this.lastActivityAt,
    this.title,
    this.origin = SessionOrigin.app,
  });

  /// Stable id.
  final String id;

  /// When the session started.
  final DateTime startedAt;

  /// Time of the last appended message (or the start).
  final DateTime lastActivityAt;

  /// Optional display title.
  final String? title;

  /// The engine that opened the session.
  final SessionOrigin origin;

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.origin == origin &&
      other.id == id &&
      other.startedAt == startedAt &&
      other.lastActivityAt == lastActivityAt &&
      other.title == title;

  @override
  int get hashCode => Object.hash(id, startedAt, lastActivityAt, title, origin);

  @override
  String toString() => 'Session($id, $startedAt–$lastActivityAt)';
}

/// A [Message] as stored in a session, with its metadata.
@immutable
final class StoredMessage {
  /// Creates a stored message.
  const StoredMessage({
    required this.id,
    required this.sessionId,
    required this.seq,
    required this.message,
    required this.createdAt,
    this.profileId,
    this.modelId,
  });

  /// Stable id.
  final String id;

  /// Owning session.
  final String sessionId;

  /// Position in the session (1, 2, 3, …).
  final int seq;

  /// The message in the core format.
  final Message message;

  /// When it was appended.
  final DateTime createdAt;

  /// Provider profile that produced it (assistant messages).
  final String? profileId;

  /// Model that produced it (assistant messages).
  final String? modelId;

  @override
  bool operator ==(Object other) =>
      other is StoredMessage &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.seq == seq &&
      other.message == message &&
      other.createdAt == createdAt &&
      other.profileId == profileId &&
      other.modelId == modelId;

  @override
  int get hashCode =>
      Object.hash(id, sessionId, seq, message, createdAt, profileId, modelId);

  @override
  String toString() => 'StoredMessage($sessionId#$seq, $message)';
}
