import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'attestation_types.dart';

/// What an [AttestationLogEntry] documents.
enum AttestationLogKind {
  /// Session attestation of the provider.
  session,

  /// Receipt check of one answer.
  receipt,

  /// NVIDIA NRAS check of the GPU evidence.
  gpu,
}

/// One line of the audit log (Prüfprotokoll): when, which provider and
/// model, the result of every stage and the receipt id. Contains no prompt
/// or answer content.
@immutable
final class AttestationLogEntry {
  /// Creates an entry.
  const AttestationLogEntry({
    required this.logId,
    required this.time,
    required this.kind,
    required this.profileId,
    required this.status,
    required this.stages,
    this.model,
    this.receiptId,
    this.repoCommit,
    this.composeHash,
    this.keysetDigest,
    this.notes = const [],
  });

  /// Id referenced by `AttestationStatusChanged.logId`.
  final String logId;

  /// When the check ran.
  final DateTime time;

  /// What was checked.
  final AttestationLogKind kind;

  /// Provider profile.
  final String profileId;

  /// Model of the answer, if any.
  final String? model;

  /// Result.
  final AttestationStatus status;

  /// Result of every stage.
  final List<StageResult> stages;

  /// Receipt id (receipt entries).
  final String? receiptId;

  /// Attested commit.
  final String? repoCommit;

  /// Attested compose hash.
  final String? composeHash;

  /// Attested keyset digest.
  final String? keysetDigest;

  /// Hints shown to the user.
  final List<String> notes;

  /// JSON for the export.
  Map<String, Object?> toJson() => {
    'logId': logId,
    'time': time.toUtc().toIso8601String(),
    'kind': kind.name,
    'profile': profileId,
    if (model != null) 'model': model,
    'status': status.name,
    'stages': [for (final s in stages) s.toJson()],
    if (receiptId != null) 'receiptId': receiptId,
    if (repoCommit != null) 'repoCommit': repoCommit,
    if (composeHash != null) 'composeHash': composeHash,
    if (keysetDigest != null) 'keysetDigest': keysetDigest,
    if (notes.isNotEmpty) 'notes': notes,
  };
}

/// Receives the audit-log entries (persisted by WP52).
abstract interface class AttestationLogSink {
  /// Stores [entry].
  void record(AttestationLogEntry entry);
}

/// [AttestationLogSink] that keeps the entries in memory.
final class InMemoryAttestationLog implements AttestationLogSink {
  /// All entries, oldest first.
  final List<AttestationLogEntry> entries = [];

  @override
  void record(AttestationLogEntry entry) => entries.add(entry);
}
