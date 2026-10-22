import 'package:wendelin_core/wendelin_core.dart';

/// Whether [e] asks the user a yes/no question (tool confirmation, hand-over
/// consent or retry offer) that the voice conversation has to wait for.
bool isQuestionEvent(AgentEvent e) =>
    e is ConfirmationRequired ||
    e is EscalationConfirmationRequired ||
    e is RetryOfferRequired;

/// Whether [e] is such a question and still unanswered.
bool isOpenQuestion(AgentEvent e) => switch (e) {
  ConfirmationRequired(:final answered) => !answered,
  EscalationConfirmationRequired(:final answered) => !answered,
  RetryOfferRequired(:final answered) => !answered,
  _ => false,
};
