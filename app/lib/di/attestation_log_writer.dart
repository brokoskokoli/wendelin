import 'dart:async';

import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

/// Reports a failed write (default: the zone's error handler).
typedef AttestationErrorHandler = void Function(Object error, StackTrace stack);

/// Persists the verification log (Prüfprotokoll) of the TEE providers.
///
/// Is the [AttestationLogSink] of the `AttestedProvider`: writes are queued
/// in order and never block the check. [attach] ties the entry to the
/// conversation step once the agent reports `AttestationStatusChanged`.
/// Only ids, hashes and stage results are stored, never content.
final class AttestationLogWriter implements AttestationLogSink {
  /// Creates the writer.
  AttestationLogWriter(this.repository, {this.onError});

  /// Target.
  final AttestationLogRepository repository;

  /// Receives write failures; `null` = current zone.
  final AttestationErrorHandler? onError;

  Future<void> _tail = Future.value();

  /// Waits until every entry recorded so far is written.
  Future<void> flush() => _tail;

  @override
  void record(AttestationLogEntry entry) =>
      _enqueue(() => repository.add(toRecord(entry)));

  /// Links the entry [logId] to [sessionId] and [stepId].
  void attach(String logId, String sessionId, String stepId) =>
      _enqueue(() => repository.attachStep(logId, sessionId, stepId));

  void _enqueue(Future<Object?> Function() write) {
    _tail = _tail.then((_) async {
      try {
        await write();
      } on Object catch (e, s) {
        (onError ?? Zone.current.handleUncaughtError)(e, s);
      }
    });
  }

  /// Maps a provider log entry to the stored form.
  static AttestationRecord toRecord(AttestationLogEntry e) {
    StageResult? stage(AttestationStage s) {
      for (final r in e.stages) {
        if (r.stage == s) return r;
      }
      return null;
    }

    // The first stage code wins: stages run in pipeline order, so the first
    // coded failure is the root cause; later codes are follow-on effects.
    final reason = e.stages
        .where((s) => s.code != null)
        .map((s) => s.code)
        .firstOrNull;
    return AttestationRecord(
      logId: e.logId,
      at: e.time,
      profileId: e.profileId,
      model: e.model,
      kind: switch (e.kind) {
        AttestationLogKind.session => AttestationRecordKind.session,
        AttestationLogKind.receipt => AttestationRecordKind.receipt,
        AttestationLogKind.gpu => AttestationRecordKind.gpu,
      },
      status: e.status,
      receiptId: e.receiptId,
      repoCommit: e.repoCommit,
      composeHash: e.composeHash,
      workloadKeysetDigest: e.keysetDigest,
      tcbStatus:
          (stage(AttestationStage.upstreamTcb) ?? stage(AttestationStage.tcb))
              ?.outcome
              .name,
      reasonCode: reason,
      stages: [
        for (final s in e.stages)
          StageRecord(
            s.stage.id,
            s.outcome.name,
            detail: _short(s.detail),
            code: s.code,
          ),
      ],
    );
  }

  static String? _short(String? s) =>
      s == null || s.length <= StageRecord.maxDetailLength
      ? s
      : '${s.substring(0, StageRecord.maxDetailLength)}…';
}
