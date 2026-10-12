import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// What an audit entry records (concept: Logging).
enum AuditKind {
  /// A user request (trigger, transcript).
  request,

  /// Routing decision (provider, model).
  routing,

  /// A tool call with arguments and result status.
  toolCall,

  /// A confirmation asked and its answer.
  confirmation,

  /// An escalation to another provider.
  escalation,

  /// Token usage and cost.
  usage,

  /// TEE verification result.
  verification,

  /// An error.
  error,
}

/// One audit log entry. [payload] must be JSON-encodable; secret-looking
/// fields are replaced by `***` when the entry is recorded.
@immutable
final class AuditEntry {
  /// Creates an entry. [id] is assigned by the repository (`null` before).
  AuditEntry({
    required this.at,
    required this.kind,
    this.sessionId,
    Map<String, Object?> payload = const {},
    this.id,
  }) : payload = Map.unmodifiable(payload);

  /// Database id (ascending in insertion order); `null` if not stored yet.
  final int? id;

  /// When it happened.
  final DateTime at;

  /// What happened.
  final AuditKind kind;

  /// Session the entry belongs to, if any.
  final String? sessionId;

  /// Details (JSON-compatible).
  final Map<String, Object?> payload;

  /// JSON form used by the export.
  Map<String, Object?> toJson() => {
    'id': id,
    'at': at.toUtc().toIso8601String(),
    'kind': kind.name,
    'sessionId': sessionId,
    'payload': payload,
  };

  @override
  bool operator ==(Object other) =>
      other is AuditEntry &&
      other.id == id &&
      other.at == at &&
      other.kind == kind &&
      other.sessionId == sessionId &&
      const DeepCollectionEquality().equals(other.payload, payload);

  @override
  int get hashCode => Object.hash(
    id,
    at,
    kind,
    sessionId,
    const DeepCollectionEquality().hash(payload),
  );

  @override
  String toString() => 'AuditEntry($id, ${kind.name}, $at)';
}

/// Filter for `AuditLogRepository.query`. All conditions are combined with
/// AND; `null` means "any".
@immutable
final class AuditFilter {
  /// Creates a filter.
  const AuditFilter({
    this.from,
    this.until,
    this.kinds,
    this.sessionId,
    this.limit,
  });

  /// Inclusive lower bound of `at`.
  final DateTime? from;

  /// Exclusive upper bound of `at`.
  final DateTime? until;

  /// Only these kinds.
  final Set<AuditKind>? kinds;

  /// Only entries of this session.
  final String? sessionId;

  /// At most this many entries (newest first).
  final int? limit;
}
