/// Verification status of TEE answers in an agent run (concept: „TEE-Provider
/// und Attestierung“, WP46): reports the status of each model call as an
/// event and holds back `external` tools until the answer is verified.
/// Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import 'run_state.dart';

/// Connects the run to providers that verify their answers afterwards
/// ([AttestationAware]). For other providers every method is a no-op.
///
/// Invariants:
/// - [AttestationStatusChanged] is emitted for each model call: yellow
///   (`logId` empty) as soon as the stream ended, then the final green or
///   red result of the same step.
/// - `external` tool calls of a verified-answer provider run only after a
///   green verification (fail-closed: red or missing result refuses them).
final class AttestationGate {
  /// Creates the gate of a run; [sessionId] prefixes the step ids.
  AttestationGate(this._control, this._sessionId);

  final RunControl _control;
  final String _sessionId;

  int _steps = 0;
  String _stepId = '';
  Future<AttestationReport?>? _report;
  bool _emitted = true;

  /// A model call on [provider] has ended: remember its pending check.
  void begin(LlmProvider provider, ChatRequest request, {bool failed = false}) {
    _stepId = '$_sessionId:${++_steps}';
    _report = provider is AttestationAware
        ? (provider as AttestationAware).reportFor(request)
        : null;
    _emitted = _report == null;
    if (_report != null && !failed) {
      // Pending (yellow) until the receipt check is final: the UI shows
      // „wird geprüft“; the final event of the same step replaces it.
      _control.emit(
        AttestationStatusChanged(
          stepId: _stepId,
          status: AttestationStatus.yellow,
          logId: '',
          detail: 'wird geprüft',
        ),
      );
    }
  }

  /// Whether the last model call's answer is verified afterwards.
  bool get expectsReport => _report != null;

  /// Waits for the final verification of the last model call, emits the
  /// status event (once) and returns the report (`null` if the provider has
  /// none or nothing was checked).
  Future<AttestationReport?> settle() async {
    final pending = _report;
    if (pending == null) return null;
    final report = await pending;
    _control.throwIfAborted();
    if (!_emitted && report != null) {
      _emitted = true;
      _control.emit(
        AttestationStatusChanged(
          stepId: _stepId,
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
