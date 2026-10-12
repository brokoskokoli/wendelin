import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'eval_case.dart';

/// A tool call the model made during a case.
@immutable
final class ObservedCall {
  /// Creates the record.
  const ObservedCall({
    required this.name,
    required this.args,
    this.rawArguments = '',
    this.isError = false,
    this.summary,
  });

  /// Tool name.
  final String name;

  /// Decoded arguments; `null` if the JSON was invalid.
  final Map<String, Object?>? args;

  /// Arguments as sent (kept when they could not be decoded).
  final String rawArguments;

  /// Whether the tool reported an error (or the call was refused).
  final bool isError;

  /// Short result text of the tool card.
  final String? summary;

  /// JSON for the report.
  Map<String, Object?> toJson() => {
    'name': name,
    if (args != null) 'args': args else 'rawArguments': rawArguments,
    if (isError) 'isError': true,
    if (summary != null) 'summary': summary,
  };
}

/// An escalation that happened during a case.
typedef ObservedEscalation = ({String to, EscalationReason reason});

/// Everything observed while the agent worked on one case.
@immutable
final class RunObservation {
  /// Creates the observation.
  const RunObservation({
    this.calls = const [],
    this.finalText = '',
    this.failure,
    this.latency = Duration.zero,
    this.usage = Usage.zero,
    this.costMicros,
    this.modelCalls = 0,
    this.confirmations = 0,
    this.escalations = const [],
    this.gaveUp = false,
  });

  /// Tool calls in order.
  final List<ObservedCall> calls;

  /// Final answer (empty if the run failed).
  final String finalText;

  /// Set when the run ended with `AgentFailed`.
  final AgentFailed? failure;

  /// Wall time from start to the terminal event.
  final Duration latency;

  /// Summed usage of all model calls.
  final Usage usage;

  /// Summed cost in micro-USD; `null` if any call had no price.
  final int? costMicros;

  /// Number of model calls (usage reports).
  final int modelCalls;

  /// Confirmations requested (answered „ja“ automatically).
  final int confirmations;

  /// Escalations, in order.
  final List<ObservedEscalation> escalations;

  /// Whether the `GiveUpClassifier` flagged an answer of the model as
  /// „kann ich nicht“ (escalated with reason `modelGaveUp`, or the final
  /// answer is classified as giving up).
  final bool gaveUp;
}

/// Outcome category of a case.
enum CaseStatus {
  /// Expectations met.
  passed,

  /// Expectations not met.
  failed,

  /// The agent run failed (`AgentFailed`) or the case could not run.
  error,

  /// Not run (pending).
  skipped,
}

/// Result of one case in a run.
@immutable
final class CaseResult {
  /// Creates a result.
  const CaseResult({
    required this.evalCase,
    required this.status,
    this.reasons = const [],
    this.observation = const RunObservation(),
  });

  /// A skipped case.
  factory CaseResult.skipped(EvalCase c, String why) =>
      CaseResult(evalCase: c, status: CaseStatus.skipped, reasons: [why]);

  /// The case.
  final EvalCase evalCase;

  /// Pass/fail/error/skipped.
  final CaseStatus status;

  /// Why it failed (or was skipped).
  final List<String> reasons;

  /// What happened.
  final RunObservation observation;

  /// Whether the case was run.
  bool get ran => status != CaseStatus.skipped;

  /// JSON for the report.
  Map<String, Object?> toJson() {
    final o = observation;
    final c = evalCase;
    return {
      'id': c.id,
      'language': c.language,
      'category': c.category,
      'prompt': c.prompt,
      'status': status.name,
      if (reasons.isNotEmpty) 'reasons': reasons,
      if (ran) ...{
        'toolCalls': [for (final call in o.calls) call.toJson()],
        'finalText': o.finalText,
        if (o.failure case final f?)
          'failure': {'kind': f.error.name, 'message': f.message},
        'latencyMs': o.latency.inMilliseconds,
        'modelCalls': o.modelCalls,
        'usage': {
          'input': o.usage.inputTokens,
          'output': o.usage.outputTokens,
          'cacheRead': o.usage.cachedInputTokens,
          'cacheWrite': o.usage.cacheWriteTokens,
        },
        'costMicros': o.costMicros,
        'confirmations': o.confirmations,
        'gaveUp': o.gaveUp,
        'escalations': [
          for (final e in o.escalations) {'to': e.to, 'reason': e.reason.name},
        ],
      },
    };
  }
}
