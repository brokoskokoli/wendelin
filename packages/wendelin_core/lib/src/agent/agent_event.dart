import '../messages/content_block.dart';
import '../messages/stop_reason.dart';
import '../messages/usage.dart';
import '../tools/tool_outcome.dart';

/// Why the agent handed a request to another provider.
enum EscalationReason {
  /// API error, timeout or rate limit.
  providerError,

  /// Invalid tool JSON or unknown tool, twice.
  invalidToolCalls,

  /// Too many tool rounds without a final answer.
  noProgress,

  /// The model said it cannot solve the task.
  modelGaveUp,

  /// The user asked for it (`UserInput.requestEscalation`).
  userRequested,
}

/// Why an agent run failed.
enum AgentErrorKind {
  /// `AgentRun.cancel` was called.
  cancelled,

  /// Total duration limit (60 s) exceeded.
  timeout,

  /// Maximum number of tool rounds (8) reached.
  toolRoundLimit,

  /// Token budget per request exhausted.
  tokenBudget,

  /// Monthly cost budget blocks further calls.
  budgetBlocked,

  /// Provider failed and no escalation target was available.
  provider,

  /// Unexpected internal error.
  internal,
}

/// Status of a TEE receipt / attestation check (placeholder until TEE).
enum VerificationStatus {
  /// Check still running.
  pending,

  /// Verified successfully.
  verified,

  /// Check failed or receipt invalid.
  failed,

  /// Could not be checked (e.g. network); will be retried.
  unavailable,
}

/// Events of one `AgentRun.run` call, consumed by the UI, TTS and audit log.
///
/// The stream ends with exactly one [AgentDone] or [AgentFailed].
sealed class AgentEvent {
  const AgentEvent();
}

/// The request was routed to [profileId] / [modelId].
final class Routed extends AgentEvent {
  /// Creates the event.
  const Routed({
    required this.profileId,
    required this.modelId,
    required this.reason,
  });

  /// Chosen provider profile.
  final String profileId;

  /// Chosen model.
  final String modelId;

  /// Why (e.g. rule name or „Standard“).
  final String reason;

  @override
  String toString() => 'Routed($profileId, $modelId, $reason)';
}

/// A piece of the answer text, streamed live.
final class AgentTextDelta extends AgentEvent {
  /// Creates the event.
  const AgentTextDelta(this.text);

  /// The text fragment.
  final String text;

  @override
  String toString() => 'AgentTextDelta($text)';
}

/// A tool call is about to be executed.
final class ToolCallStarted extends AgentEvent {
  /// Creates the event.
  const ToolCallStarted(this.call);

  /// The call.
  final ToolCallBlock call;

  @override
  String toString() => 'ToolCallStarted(${call.name})';
}

/// The user must confirm [call]; call [respond] exactly once.
final class ConfirmationRequired extends AgentEvent {
  /// Creates the event.
  const ConfirmationRequired({
    required this.call,
    required this.description,
    required this.respond,
  });

  /// The call awaiting confirmation.
  final ToolCallBlock call;

  /// German text for the confirmation card.
  final String description;

  /// Answer: `true` = execute, `false` = decline.
  final void Function(bool approved) respond;

  @override
  String toString() => 'ConfirmationRequired(${call.name}, $description)';
}

/// A tool call has finished (successfully, with error, or declined).
final class ToolCallFinished extends AgentEvent {
  /// Creates the event.
  const ToolCallFinished({
    required this.call,
    required this.outcome,
    this.duration,
  });

  /// The call.
  final ToolCallBlock call;

  /// Its outcome (with summary and undo for the tool card).
  final ToolOutcome outcome;

  /// Execution time, if measured.
  final Duration? duration;

  @override
  String toString() => 'ToolCallFinished(${call.name}, $outcome)';
}

/// The request was handed to a stronger / different provider.
final class Escalated extends AgentEvent {
  /// Creates the event.
  const Escalated({
    required this.fromProfile,
    required this.toProfile,
    required this.reason,
  });

  /// Previous profile id.
  final String fromProfile;

  /// New profile id.
  final String toProfile;

  /// Why.
  final EscalationReason reason;

  @override
  String toString() => 'Escalated($fromProfile → $toProfile, ${reason.name})';
}

/// Usage (and cost) of one model call.
final class UsageReported extends AgentEvent {
  /// Creates the event.
  const UsageReported({
    required this.profileId,
    required this.modelId,
    required this.usage,
    this.costMicros,
  });

  /// Provider profile of the call.
  final String profileId;

  /// Model of the call.
  final String modelId;

  /// Tokens used.
  final Usage usage;

  /// Cost in micro-USD, if prices are known.
  final int? costMicros;

  @override
  String toString() => 'UsageReported($profileId, $modelId, $usage)';
}

/// Result of a TEE verification step (placeholder; filled in with TEE
/// support).
final class Verification extends AgentEvent {
  /// Creates the event.
  const Verification({
    required this.profileId,
    required this.status,
    this.detail,
  });

  /// Provider profile being verified.
  final String profileId;

  /// Outcome of the check.
  final VerificationStatus status;

  /// Additional information (e.g. receipt id), secret-free.
  final String? detail;

  @override
  String toString() => 'Verification($profileId, ${status.name})';
}

/// The run finished with a final answer (terminal).
final class AgentDone extends AgentEvent {
  /// Creates the event.
  const AgentDone({required this.finalText, required this.stopReason});

  /// Complete answer text of the last model turn.
  final String finalText;

  /// Stop reason of the last model call.
  final StopReason stopReason;

  @override
  String toString() => 'AgentDone(${stopReason.name}, $finalText)';
}

/// The run failed (terminal).
final class AgentFailed extends AgentEvent {
  /// Creates the event.
  const AgentFailed({required this.error, required this.message, this.cause});

  /// Kind of failure.
  final AgentErrorKind error;

  /// German, secret-free message for the user.
  final String message;

  /// Underlying exception, if any (e.g. a `ProviderException`).
  final Object? cause;

  @override
  String toString() => 'AgentFailed(${error.name}, $message)';
}
