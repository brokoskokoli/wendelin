import 'agent_event.dart';
import 'user_input.dart';

/// One provider-independent agent loop (implemented by `AgentRunner` in
/// `wendelin_agent`): build context, call the model, run tools, repeat.
abstract interface class AgentRun {
  /// Processes [input]; the stream ends with `AgentDone` or `AgentFailed`.
  Stream<AgentEvent> run(UserInput input);

  /// Aborts the current run (model call and running tools); the stream then
  /// ends with `AgentFailed(error: AgentErrorKind.cancelled)`.
  void cancel();
}
