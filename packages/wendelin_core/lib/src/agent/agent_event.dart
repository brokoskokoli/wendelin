import '../messages/content_block.dart';
import '../messages/stop_reason.dart';
import '../messages/usage.dart';
import '../provider/attestation.dart';
import '../tools/tool.dart';
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

/// The separate spoken version of the answer (WP41, stage 2): the
/// `<spoken>` block at the start of the model's text, complete. It is only
/// for speech output: never shown, not part of the history and not part of
/// the final text.
final class AgentSpokenText extends AgentEvent {
  /// Creates the event.
  const AgentSpokenText(this.text);

  /// The text to speak.
  final String text;

  @override
  String toString() => 'AgentSpokenText($text)';
}

/// The spoken text of the current model call is held back until a check
/// (WP55, [SpokenVersion.checked]) has decided: the speech output must not
/// read the written text of this segment yet. Ends with [AgentSpokenVerdict]
/// (and, if accepted, [AgentSpokenText]); an [AgentTextReset] or the end of
/// the segment also ends the hold.
final class AgentSpokenHold extends AgentEvent {
  /// Creates the event.
  const AgentSpokenHold();

  @override
  String toString() => 'AgentSpokenHold()';
}

/// The result of the check of the spoken text against the written answer
/// (WP55). When [accepted] the spoken text follows as [AgentSpokenText];
/// else the written answer is read out and the UI may say so. [reason] is
/// short and without answer content (it goes to the audit log).
final class AgentSpokenVerdict extends AgentEvent {
  /// Creates the event.
  const AgentSpokenVerdict({required this.accepted, required this.reason});

  /// Whether the spoken text is read out.
  final bool accepted;

  /// Why (short, one line).
  final String reason;

  @override
  String toString() => 'AgentSpokenVerdict($accepted, $reason)';
}

/// The text streamed by the current model call is discarded – e.g. because
/// the call is retried or the answer is handed to another provider.
///
/// "Current model call" means: all [AgentTextDelta]s since the most recent
/// [ToolCallStarted], [ToolCallFinished], [AgentTextReset] or the start of
/// the run, whichever came last. Text of earlier, kept rounds stays visible.
/// UI and TTS drop what they showed or buffered for that segment only.
final class AgentTextReset extends AgentEvent {
  /// Creates the event.
  const AgentTextReset(this.reason);

  /// Why the text was discarded (for display/log only).
  final String reason;

  @override
  String toString() => 'AgentTextReset($reason)';
}

/// A thinking/reasoning fragment from the model (display only, never spoken).
final class AgentThinkingDelta extends AgentEvent {
  /// Creates the event.
  const AgentThinkingDelta(this.text);

  /// The fragment.
  final String text;

  @override
  String toString() => 'AgentThinkingDelta(${text.length} chars)';
}

/// The monthly budget of a provider profile reached its warning threshold.
/// The run continues; a blocked budget ends the run with [AgentFailed].
final class BudgetWarning extends AgentEvent {
  /// Creates the event.
  const BudgetWarning({
    required this.profileId,
    required this.spentMicros,
    required this.budgetMicros,
  });

  /// The affected profile.
  final String profileId;

  /// Spent this month in micro-USD.
  final int spentMicros;

  /// Monthly budget in micro-USD.
  final int budgetMicros;

  @override
  String toString() => 'BudgetWarning($profileId, $spentMicros/$budgetMicros)';
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

/// The user must confirm [call]. Answer with [respond].
final class ConfirmationRequired extends AgentEvent {
  /// Creates the event; [respond] forwards the answer to the agent.
  ConfirmationRequired({
    required this.call,
    required this.description,
    required void Function(bool approved) respond,
    this.risk = RiskLevel.external,
  }) : _answer = _Once(respond);

  /// The call awaiting confirmation.
  final ToolCallBlock call;

  /// German text for the confirmation card.
  final String description;

  /// Effective risk level of the call (see `ConfirmationNeeded.risk`).
  final RiskLevel risk;

  final _Once _answer;

  /// Whether an answer has already been given.
  bool get answered => _answer.done;

  /// Answers: `true` = execute, `false` = decline. Idempotent: the first
  /// answer wins, later calls are ignored.
  void respond(bool approved) => _answer(approved);

  @override
  String toString() =>
      'ConfirmationRequired(${call.name}, ${risk.name}, $description)';
}

/// The agent wants to escalate to a provider with a **lower** privacy level
/// than the current request requires (concept: „Datenschutz-Grenze … außer
/// der Nutzer bestätigt“). Nothing is sent to [toProfile] before the user
/// approves via [respond]; declining ends or continues the run without that
/// escalation.
final class EscalationConfirmationRequired extends AgentEvent {
  /// Creates the event; [respond] forwards the answer to the agent.
  EscalationConfirmationRequired({
    required this.fromProfile,
    required this.toProfile,
    required this.reason,
    required void Function(bool approved) respond,
  }) : _answer = _Once(respond);

  /// Current profile id.
  final String fromProfile;

  /// Proposed profile id (lower privacy level).
  final String toProfile;

  /// Why the agent wants to escalate.
  final EscalationReason reason;

  final _Once _answer;

  /// Whether an answer has already been given.
  bool get answered => _answer.done;

  /// Answers: `true` = escalate, `false` = stay. Idempotent: the first
  /// answer wins, later calls are ignored.
  void respond(bool approved) => _answer(approved);

  @override
  String toString() =>
      'EscalationConfirmationRequired($fromProfile → $toProfile, '
      '${reason.name})';
}

/// Forwards only the first answer.
final class _Once {
  _Once(this._target);

  final void Function(bool) _target;
  bool done = false;

  void call(bool value) {
    if (done) return;
    done = true;
    _target(value);
  }
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

/// Verification result of one TEE answer (or of the session): [status] is
/// the traffic light shown at the conversation step, [logId] names the entry
/// in the audit log (Prüfprotokoll) with the result of every check stage.
/// Final per answer is green or red; yellow only while a check is pending
/// or being retried.
final class AttestationStatusChanged extends AgentEvent {
  /// Creates the event.
  const AttestationStatusChanged({
    required this.stepId,
    required this.status,
    required this.logId,
    this.detail,
  });

  /// The conversation step (model call) the status belongs to.
  final String stepId;

  /// Traffic light.
  final AttestationStatus status;

  /// Id of the audit-log entry.
  final String logId;

  /// Short German hint (e.g. TCB note), secret-free.
  final String? detail;

  @override
  String toString() => 'AttestationStatusChanged($stepId, ${status.name})';
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
