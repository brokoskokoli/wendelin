import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// Version of the JSON export format of the verification log.
const attestationExportVersion = 1;

/// What an [AttestationRecord] documents.
enum AttestationRecordKind {
  /// Session attestation of the provider.
  session,

  /// Receipt check of one answer.
  receipt,

  /// NVIDIA check of the GPU evidence.
  gpu,
}

/// Result of one check stage: [stage] is a stable id, [result] one of
/// `pass`, `warn`, `fail`, `unavailable`, `info`; [detail] is a short,
/// secret-free reason (never content).
@immutable
final class StageRecord {
  /// Creates a stage record.
  const StageRecord(this.stage, this.result, {this.detail, this.code});

  /// Reads the JSON form.
  factory StageRecord.fromJson(Map<String, Object?> json) => StageRecord(
    json['stage']! as String,
    json['result']! as String,
    detail: json['detail'] as String?,
    code: json['code'] as String?,
  );

  /// Stage id.
  final String stage;

  /// Outcome name.
  final String result;

  /// Short reason.
  final String? detail;

  /// Stable reason code (e.g. `upstream_tcb_out_of_date`).
  final String? code;

  /// Maximum length of a stored [detail]; longer texts are cut by the
  /// repository (server texts must not bloat the log).
  static const maxDetailLength = 200;

  /// Copy whose [detail] is cut to [maxDetailLength] characters plus `…`.
  StageRecord shortened() => detail == null || detail!.length <= maxDetailLength
      ? this
      : StageRecord(
          stage,
          result,
          detail: '${detail!.substring(0, maxDetailLength)}…',
          code: code,
        );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'stage': stage,
    'result': result,
    'detail': ?detail,
    'code': ?code,
  };

  @override
  bool operator ==(Object other) =>
      other is StageRecord &&
      other.stage == stage &&
      other.result == result &&
      other.detail == detail &&
      other.code == code;

  @override
  int get hashCode => Object.hash(stage, result, detail, code);
}

/// One line of the verification log. Holds only ids, hashes and stage
/// results: no prompt or answer content and no raw receipt.
@immutable
final class AttestationRecord {
  /// Creates a record. [id] is assigned by the repository.
  AttestationRecord({
    required this.logId,
    required this.at,
    required this.profileId,
    required this.kind,
    required this.status,
    List<StageRecord> stages = const [],
    this.model,
    this.sessionId,
    this.stepId,
    this.receiptId,
    this.workloadKeysetDigest,
    this.workloadId,
    this.repoCommit,
    this.composeHash,
    this.tcbStatus,
    this.reasonCode,
    this.id,
  }) : stages = List.unmodifiable(stages);

  /// Database id; `null` before storing.
  final int? id;

  /// Id of the agent event `AttestationStatusChanged.logId`.
  final String logId;

  /// When the check ran.
  final DateTime at;

  /// Provider profile.
  final String profileId;

  /// Model of the answer.
  final String? model;

  /// What was checked.
  final AttestationRecordKind kind;

  /// Conversation session.
  final String? sessionId;

  /// Conversation step (message/model call).
  final String? stepId;

  /// Receipt id.
  final String? receiptId;

  /// Attested keyset digest of the workload.
  final String? workloadKeysetDigest;

  /// Workload id, if the provider names one.
  final String? workloadId;

  /// Attested commit.
  final String? repoCommit;

  /// Compose hash or image digest.
  final String? composeHash;

  /// Overall result.
  final AttestationStatus status;

  /// Result of every stage.
  final List<StageRecord> stages;

  /// Platform TCB status (stage outcome name), if checked.
  final String? tcbStatus;

  /// Stable reason of a non-green result, e.g. `upstream_tcb_out_of_date`.
  final String? reasonCode;

  /// Copy with the conversation reference set.
  AttestationRecord withStep(String? sessionId, String? stepId) =>
      AttestationRecord(
        id: id,
        logId: logId,
        at: at,
        profileId: profileId,
        model: model,
        kind: kind,
        sessionId: sessionId,
        stepId: stepId,
        receiptId: receiptId,
        workloadKeysetDigest: workloadKeysetDigest,
        workloadId: workloadId,
        repoCommit: repoCommit,
        composeHash: composeHash,
        status: status,
        stages: stages,
        tcbStatus: tcbStatus,
        reasonCode: reasonCode,
      );

  /// JSON form used by the export (UTC time, absent fields omitted).
  Map<String, Object?> toJson() => {
    'logId': logId,
    'at': at.toUtc().toIso8601String(),
    'profileId': profileId,
    'model': ?model,
    'kind': kind.name,
    'sessionId': ?sessionId,
    'stepId': ?stepId,
    'receiptId': ?receiptId,
    'workloadKeysetDigest': ?workloadKeysetDigest,
    'workloadId': ?workloadId,
    'repoCommit': ?repoCommit,
    'composeHash': ?composeHash,
    'status': status.name,
    'stages': [for (final s in stages) s.toJson()],
    'tcbStatus': ?tcbStatus,
    'reasonCode': ?reasonCode,
  };

  @override
  bool operator ==(Object other) =>
      other is AttestationRecord &&
      other.logId == logId &&
      other.at == at &&
      other.profileId == profileId &&
      other.model == model &&
      other.kind == kind &&
      other.sessionId == sessionId &&
      other.stepId == stepId &&
      other.receiptId == receiptId &&
      other.workloadKeysetDigest == workloadKeysetDigest &&
      other.workloadId == workloadId &&
      other.repoCommit == repoCommit &&
      other.composeHash == composeHash &&
      other.status == status &&
      const ListEquality<StageRecord>().equals(other.stages, stages) &&
      other.tcbStatus == tcbStatus &&
      other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(logId, at, profileId, kind, status);

  @override
  String toString() => 'AttestationRecord($logId, ${status.name})';
}
