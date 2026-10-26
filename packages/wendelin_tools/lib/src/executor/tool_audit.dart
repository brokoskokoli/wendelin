import 'package:meta/meta.dart';

/// How the policy/user decided about a call.
enum AuditDecision {
  /// Ran without asking.
  allowed,

  /// The user confirmed.
  confirmed,

  /// The user declined (or the run was cancelled during the question).
  declined,

  /// The policy denied the call.
  denied,

  /// No decision was reached (unknown tool, invalid arguments, cancelled
  /// before the policy was consulted).
  none,
}

/// How a call ended.
enum AuditStatus {
  /// The tool returned a normal outcome.
  ok,

  /// The tool returned an error outcome or threw.
  error,

  /// The tool did not finish within the timeout.
  timeout,

  /// The user declined.
  declined,

  /// The policy denied the call.
  denied,

  /// The run was cancelled before the tool finished.
  cancelled,

  /// No such (active) tool.
  unknownTool,

  /// Arguments were no JSON object or violated the schema.
  invalidArguments,
}

/// One executed (or refused) tool call for the audit log.
@immutable
final class ToolAuditEntry {
  /// Creates an entry.
  const ToolAuditEntry({
    required this.sessionId,
    required this.callId,
    required this.tool,
    required this.argumentsJson,
    required this.decision,
    required this.status,
    required this.duration,
    this.whileLocked = false,
  });

  /// Session of the run.
  final String sessionId;

  /// Provider call id.
  final String callId;

  /// Tool name as requested by the model.
  final String tool;

  /// Arguments exactly as sent by the model.
  final String argumentsJson;

  /// Policy/user decision.
  final AuditDecision decision;

  /// How the call ended.
  final AuditStatus status;

  /// Time from start to finish (including waiting for confirmation).
  final Duration duration;

  /// The call came from a locked device (WP154 L2).
  final bool whileLocked;

  @override
  String toString() =>
      'ToolAuditEntry($callId, $tool, ${decision.name}, ${status.name})';
}

/// Receives one [ToolAuditEntry] per finished call. Implemented by storage
/// (audit log in SQLite) and wired by the app.
abstract interface class ToolAuditSink {
  /// Records [entry]. Must not throw; errors are reported to the current
  /// zone and do not affect the tool run.
  void record(ToolAuditEntry entry);
}
