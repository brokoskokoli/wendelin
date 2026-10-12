import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../model/audit_entry.dart';
import '../redaction.dart';
import '../repositories/repositories.dart';
import 'database.dart';

/// drift implementation of [AuditLogRepository].
final class DriftAuditLogRepository implements AuditLogRepository {
  /// Creates the repository.
  DriftAuditLogRepository(this._db, this._clock);

  final WendelinDatabase _db;
  final Clock _clock;

  @override
  Future<AuditEntry> record(AuditEntry entry) async {
    final payload = redactSecrets(entry.payload)! as Map<String, Object?>;
    final id = await _db
        .into(_db.auditLog)
        .insert(
          AuditLogCompanion.insert(
            at: entry.at,
            kind: entry.kind,
            sessionId: Value(entry.sessionId),
            payloadJson: jsonEncode(payload),
          ),
        );
    return AuditEntry(
      id: id,
      at: entry.at,
      kind: entry.kind,
      sessionId: entry.sessionId,
      payload: payload,
    );
  }

  @override
  Future<List<AuditEntry>> query([
    AuditFilter filter = const AuditFilter(),
  ]) async {
    final q = _db.select(_db.auditLog)
      ..orderBy([
        (a) => OrderingTerm.desc(a.at),
        (a) => OrderingTerm.desc(a.id),
      ]);
    final from = filter.from;
    final until = filter.until;
    final kinds = filter.kinds;
    final sessionId = filter.sessionId;
    final limit = filter.limit;
    if (from != null) {
      q.where((a) => a.at.isBiggerOrEqualValue(from.microsecondsSinceEpoch));
    }
    if (until != null) {
      q.where((a) => a.at.isSmallerThanValue(until.microsecondsSinceEpoch));
    }
    if (kinds != null) {
      q.where((a) => a.kind.isIn([for (final k in kinds) k.name]));
    }
    if (sessionId != null) q.where((a) => a.sessionId.equals(sessionId));
    if (limit != null) q.limit(limit);
    return (await q.get()).map(_entry).toList();
  }

  @override
  Future<int> purgeOlderThan([
    Duration maxAge = AuditLogRepository.defaultRetention,
  ]) {
    final cutoff = _clock.now().subtract(maxAge).microsecondsSinceEpoch;
    return (_db.delete(
      _db.auditLog,
    )..where((a) => a.at.isSmallerThanValue(cutoff))).go();
  }

  @override
  Future<String> exportJson() async {
    final rows =
        await (_db.select(_db.auditLog)..orderBy([
              (a) => OrderingTerm.asc(a.at),
              (a) => OrderingTerm.asc(a.id),
            ]))
            .get();
    return const JsonEncoder.withIndent('  ')
        .convert([for (final r in rows) _entry(r).toJson()]);
  }

  @override
  Future<void> clear() => _db.delete(_db.auditLog).go();

  static AuditEntry _entry(AuditRow r) => AuditEntry(
    id: r.id,
    at: r.at,
    kind: r.kind,
    sessionId: r.sessionId,
    payload: jsonDecode(r.payloadJson) as Map<String, Object?>,
  );
}
