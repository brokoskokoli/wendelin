/// Verification status of TEE answers in an agent run (concept: „TEE-Provider
/// und Attestierung“, WP46): reports the status of each model call as an
/// event and holds back `external` tools until the answer is verified.
/// Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import 'run_state.dart';

/// The check of one model call: its step id, pending report and the sink its
/// status events go to (a buffer for a call that overlaps the previous check).
final class AttestationStep {
  AttestationStep._(this.id, this.report, this.sink) : emitted = report == null;

  /// Id of the step (`<session>:<n>`).
  final String id;

  /// The pending check; `null` if the provider does not verify its answers.
  final Future<AttestationReport?>? report;

  /// Where the events of this step go.
  final RunControl sink;

  /// Whether the final status event went out.
  bool emitted;
}

/// Connects the run to providers that verify their answers afterwards
/// ([AttestationAware]). For other providers every method is a no-op.
///
/// Invariants:
/// - [AttestationStatusChanged] is emitted for each model call: yellow
///   (`logId` empty) as soon as the stream ended, then the final green or
///   red result of the same step.
/// - Each model call has its own [AttestationStep]: a call started while the
///   check of the previous answer is still open (WP81b) never overwrites its
///   step id, report or events.
/// - `external` tool calls of a verified-answer provider run only after a
///   green verification (fail-closed: red or missing result refuses them).
final class AttestationGate {
  /// Creates the gate of a run; [sessionId] prefixes the step ids.
  AttestationGate(this._control, this._sessionId);

  final RunControl _control;
  final String _sessionId;

  int _steps = 0;

  /// A model call on [provider] has ended: remember its pending check.
  /// Events of the step go to [sink] (default: the run).
  AttestationStep begin(
    LlmProvider provider,
    ChatRequest request, {
    bool failed = false,
    RunControl? sink,
  }) {
    final report = provider is AttestationAware
        ? (provider as AttestationAware).reportFor(request)
        : null;
    // The check of a discarded call may fail unobserved.
    report?.ignore();
    final step = AttestationStep._(
      '$_sessionId:${++_steps}',
      report,
      sink ?? _control,
    );
    if (report != null && !failed) {
      // Pending (yellow) until the receipt check is final: the UI shows
      // „wird geprüft“; the final event of the same step replaces it.
      step.sink.emit(
        AttestationStatusChanged(
          stepId: step.id,
          status: AttestationStatus.yellow,
          logId: '',
          detail: 'wird geprüft',
        ),
      );
    }
    return step;
  }

  /// Waits for the final verification of [step] (the step of the answer in
  /// question, never "the latest": calls overlap), emits the status event
  /// (once) and returns the report (`null` if the provider has none or
  /// nothing was checked).
  ///
  /// An abort while the receipt is open ends the run with the abort and
  /// emits no final status event: the yellow event stays the last one.
  Future<AttestationReport?> settle(
    AttestationStep? step, {
    void Function()? onNotGreen,
  }) async {
    final target = step;
    final pending = target?.report;
    if (target == null || pending == null) return null;
    // An abort does not wait for the receipt.
    final report = await Future.any([
      pending,
      _control.token.whenCancelled.then<AttestationReport?>((_) => null),
    ]);
    _control.throwIfAborted();
    if (report?.status != AttestationStatus.green) onNotGreen?.call();
    if (!target.emitted && report != null) {
      target.emitted = true;
      target.sink.emit(
        AttestationStatusChanged(
          stepId: target.id,
          status: report.status,
          logId: report.logId,
          detail: report.detail,
          reasonCode: report.reasonCode,
          toolsInvolved: report.toolsInvolved,
        ),
      );
    }
    return report;
  }
}
