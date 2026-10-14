import 'package:meta/meta.dart';

import '../messages/chat_request.dart';

/// Traffic light of a TEE check (concept: „TEE-Provider und Attestierung“).
enum AttestationStatus {
  /// All checks passed.
  green,

  /// A check is pending, could not be completed yet (network) or is being
  /// retried. Never a final result per answer.
  yellow,

  /// A check failed.
  red,
}

/// Result of verifying one answer (or the session) of a TEE provider.
@immutable
final class AttestationReport {
  /// Creates the report.
  const AttestationReport({
    required this.logId,
    required this.status,
    this.detail,
    this.reasonCode,
  });

  /// Id of the audit-log entry with every check stage.
  final String logId;

  /// Traffic light.
  final AttestationStatus status;

  /// Short German hint, secret-free (never prompt or receipt content).
  final String? detail;

  /// Stable machine-readable reason of a non-green result, if it has a
  /// special one the UI can tell apart from manipulation, e.g.
  /// `upstream_tcb_out_of_date` (operator's security update pending).
  final String? reasonCode;

  @override
  bool operator ==(Object other) =>
      other is AttestationReport &&
      other.logId == logId &&
      other.status == status &&
      other.detail == detail &&
      other.reasonCode == reasonCode;

  @override
  int get hashCode => Object.hash(logId, status, detail, reasonCode);

  @override
  String toString() => 'AttestationReport($logId, ${status.name})';
}

/// Capability of an [LlmProvider] that verifies its answers afterwards (the
/// `AttestedProvider` decorator). The agent loop uses it to report the
/// status and to hold back `external` tools until the answer is verified.
abstract interface class AttestationAware {
  /// Results that arrive after the answer stream ended (receipt checks,
  /// asynchronous GPU checks). Broadcast stream.
  Stream<AttestationReport> get reports;

  /// Completes with the verification result of the `chat` call made with
  /// [request] (identity of the object) once its receipt check is final
  /// (green or red); `null` if that call needs no check (e.g. it failed
  /// before any answer). Bound per call, so parallel runs on one provider
  /// never see each other's result. Call it after the stream ended.
  Future<AttestationReport?> reportFor(ChatRequest request);
}
