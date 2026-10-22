import '../di/audit_recorder.dart';
import 'conversation_state.dart';

/// Gives the user's answer to the open [question] to the agent run and writes
/// it to the audit log (tool confirmation, escalation consent, retry offer).
void answerQuestion(
  PendingQuestion question,
  AuditRecorder audit,
  String sessionId, {
  required bool approved,
}) {
  switch (question) {
    case ToolQuestion(:final event):
      event.respond(approved);
      audit.toolConfirmation(sessionId, event, approved: approved);
    case EscalationQuestion(:final event):
      event.respond(approved);
      audit.escalationConfirmation(sessionId, event, approved: approved);
    case RetryOfferQuestion(:final event):
      event.respond(approved);
      audit.retryOffer(sessionId, event, approved: approved);
  }
}
