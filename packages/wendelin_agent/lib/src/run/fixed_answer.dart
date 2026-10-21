/// Fixed confirmation sentences (WP122): a tool round whose calls all
/// succeeded and all have a template ends the request without a second model
/// call. Internal to `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import 'privacy_scope.dart';
import 'run_config.dart';
import 'run_state.dart';
import 'tool_round.dart';

/// Builds and delivers the fixed answer of a tool round.
///
/// Invariants:
/// - Only when every call of the round ran through the invoker, succeeded
///   (not an error, not declined), belongs to a [FixedConfirmationTool] and
///   carries a sentence whose key the tool declared. Anything else (error,
///   question, read tool, tool without template, refused or repeated call,
///   unknown language) returns `null`: the model answers as before.
/// - The sentence is delivered only after a green receipt of the answer that
///   asked for the tools (fail-closed); it is built from the tool results
///   only. With a red receipt the undo ran in [ToolRound.verify], and the
///   run goes on with the model (it sees the undone results).
/// - The sentence is the assistant's answer in the history, so follow-up
///   questions work; no model call is made (no overlap call either).
/// - Text the first model reply already streamed or spoke stays: its
///   segment ended with the first tool event, so a reset could not take it
///   back (and speech may already have started). The sentence follows it.
/// - Only `confirm=fixed tool=<name>` is reported
///   ([RunConfig.onFixedConfirmation]); the sentence itself never.
final class FixedAnswer {
  /// Creates the unit of [runner]'s run.
  FixedAnswer(
    this.runner,
    this._state,
    this._privacy,
    this._control,
    this._tools,
  );

  /// The runner (callbacks).
  final RunConfig runner;
  final RunState _state;
  final PrivacyScope _privacy;
  final RunControl _control;
  final ToolRound _tools;

  /// The sentence for [round] in [language], or `null` (model answers).
  String? sentenceFor(ToolRoundRun round, String? language) {
    // Second safeguard: a rejected or repeated call has no `executed` entry
    // with its id, so the lookup below already returns null for it. This
    // check is deliberately redundant (equivalent mutation, no own test).
    if (round.calls.isEmpty || round.pending.length != round.calls.length) {
      return null;
    }
    final sentences = <String>[];
    for (final call in round.calls) {
      Executed? ran;
      for (final e in _state.executed) {
        if (e.call.id == call.id) ran = e;
      }
      final outcome = ran?.outcome;
      final tool = _privacy.catalog.lookup(call.name);
      final sentence = outcome?.fixed;
      if (outcome == null ||
          outcome.isError ||
          sentence == null ||
          tool is! FixedConfirmationTool ||
          !(tool as FixedConfirmationTool).confirmationKeys.contains(
            sentence.key,
          )) {
        return null;
      }
      final text = renderConfirmation(sentence, language);
      if (text == null) return null;
      sentences.add(text);
    }
    return joinConfirmations(sentences);
  }

  /// Delivers [sentence] as the answer of the run if the answer that asked
  /// for [round] is verified; returns the terminal event. Without a green
  /// receipt the results are recorded (the undo ran) and `null` is returned:
  /// the loop then calls the model.
  Future<AgentDone?> finish(ToolRoundRun round, String sentence) async {
    final green = await _tools.verify(round);
    final verified = round.step?.report == null || green;
    await _state.append(Message.toolResults(_tools.resultsOf(round)));
    _control.throwIfAborted();
    if (!verified) return null;
    for (final call in round.calls) {
      runner.onFixedConfirmation?.call(runner.sessionId, call.name);
    }
    _control.emit(AgentTextDelta(sentence));
    final answer = Message.assistant([TextBlock(sentence)]);
    final text = [..._state.paused, answer].map((m) => m.text).join();
    await _state.append(answer);
    return AgentDone(
      finalText: text,
      stopReason: StopReason.endTurn,
      fixed: true,
    );
  }
}
