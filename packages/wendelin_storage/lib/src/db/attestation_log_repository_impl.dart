import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../model/attestation_record.dart';
import '../repositories/repositories.dart';
import 'database.dart';

/// drift implementation of [AttestationLogRepository].
final class DriftAttestationLogRepository implements AttestationLogRepository {
  /// Creates the repository.
  DriftAttestationLogRepository(this._db, this._clock);

  final WendelinDatabase _db;
  final Clock _clock;

  @override
  Future<void> add(AttestationRecord record) async {
    await _db
        .into(_db.attestationLog)
        .insert(
          AttestationLogCompanion.insert(
            logId: record.logId,
            at: record.at,
            profileId: record.profileId,
            model: Value(record.model),
            kind: record.kind.name,
            sessionId: Value(record.sessionId),
            stepId: Value(record.stepId),
            receiptId: Value(record.receiptId),
            workloadKeysetDigest: Value(record.workloadKeysetDigest),
            workloadId: Value(record.workloadId),
            repoCommit: Value(record.repoCommit),
            composeHash: Value(record.composeHash),
            status: record.status.name,
            stagesJson: jsonEncode([for (final s in record.stages) s.toJson()]),
            tcbStatus: Value(record.tcbStatus),
            reasonCode: Value(record.reasonCode),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<bool> attachStep(String logId, String sessionId, String stepId) async {
    final n =
        await (_db.update(
          _db.attestationLog,
        )..where((a) => a.logId.equals(logId))).write(
          AttestationLogCompanion(
            sessionId: Value(sessionId),
            stepId: Value(stepId),
          ),
        );
    return n > 0;
  }

  @override
  Future<AttestationRecord?> byLogId(String logId) async {
    final row = await (_db.select(
      _db.attestationLog,
    )..where((a) => a.logId.equals(logId))).getSingleOrNull();
    return row == null ? null : _record(row);
  }

  @override
  Future<List<AttestationRecord>> forSession(String sessionId) =>
      _query((a) => a.sessionId.equals(sessionId), asc: true);

  @override
  Future<List<AttestationRecord>> forStep(String stepId) =>
      _query((a) => a.stepId.equals(stepId), asc: true);

  @override
  Future<List<AttestationRecord>> latest({int limit = 50}) =>
      _query(null, limit: limit);

  @override
  Future<int> purgeOlderThan([
    Duration maxAge = AttestationLogRepository.defaultRetention,
  ]) {
    final cutoff = _clock.now().subtract(maxAge).microsecondsSinceEpoch;
    return (_db.delete(
      _db.attestationLog,
    )..where((a) => a.at.isSmallerThanValue(cutoff))).go();
  }

  @override
  Future<void> deleteAll() => _db.delete(_db.attestationLog).go();

  @override
  Future<String> exportJson() async {
    final rows =
        await (_db.select(_db.attestationLog)..orderBy([
              (a) => OrderingTerm.asc(a.at),
              (a) => OrderingTerm.asc(a.id),
            ]))
            .get();
    return const JsonEncoder.withIndent('  ').convert({
      'version': attestationExportVersion,
      'entries': [for (final r in rows) _record(r).toJson()],
    });
  }

  Future<List<AttestationRecord>> _query(
    Expression<bool> Function($AttestationLogTable)? where, {
    bool asc = false,
    int? limit,
  }) async {
    final q = _db.select(_db.attestationLog)
      ..orderBy([
        (a) => asc ? OrderingTerm.asc(a.at) : OrderingTerm.desc(a.at),
        (a) => asc ? OrderingTerm.asc(a.id) : OrderingTerm.desc(a.id),
      ]);
    if (where != null) q.where(where);
    if (limit != null) q.limit(limit);
    return (await q.get()).map(_record).toList();
  }

  static AttestationRecord _record(AttestationRow r) => AttestationRecord(
    id: r.id,
    logId: r.logId,
    at: r.at,
    profileId: r.profileId,
    model: r.model,
    kind: AttestationRecordKind.values.byName(r.kind),
    sessionId: r.sessionId,
    stepId: r.stepId,
    receiptId: r.receiptId,
    workloadKeysetDigest: r.workloadKeysetDigest,
    workloadId: r.workloadId,
    repoCommit: r.repoCommit,
    composeHash: r.composeHash,
    status: AttestationStatus.values.byName(r.status),
    stages: [
      for (final s in jsonDecode(r.stagesJson) as List<Object?>)
        StageRecord.fromJson(s! as Map<String, Object?>),
    ],
    tcbStatus: r.tcbStatus,
    reasonCode: r.reasonCode,
  );
}
