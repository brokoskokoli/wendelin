/// The fast path before the first model call (WP135 D): a simple request an
/// integration recognizes locally runs as a tool call without a model.
/// Internal to `wendelin_agent`, not exported.
library;

import 'dart:convert';

import 'package:wendelin_core/wendelin_core.dart';

import 'fixed_answer.dart';
import 'privacy_scope.dart';
import 'run_config.dart';
import 'run_state.dart';
import 'tool_round.dart';

/// Lowest speech recognition confidence at which a spoken request may take
/// the fast path; below it the model decides (a misheard command is not run
/// directly). Typed input has no confidence.
const fastPathMinConfidence = 0.6;

/// Runs a [FastPath] match as one tool round.
///
/// Invariants:
/// - The call goes through the same unit as a model call ([ToolRound]):
///   catalog check, executor (risk policy, confirmation, audit), undo,
///   history. The fast path has no powers of its own.
/// - Only a tool of the current target's catalog that declares fixed
///   confirmation sentences ([FixedConfirmationTool]) is run; anything else
///   gives `null` and the model answers.
/// - It ends the request only with a fixed sentence built from the tool
///   result ([FixedAnswer]). If the call fails, is declined or has no
///   sentence, the model takes over and sees the call and its result in the
///   conversation, as if it had made the call itself.
/// - A repeated turn („nochmal mit …“), a request with images, a spoken
///   request with low confidence and a matcher that throws never take the
///   fast path (fail-closed).
/// - No model call happens, so no budget is spent and no receipt exists.
final class FastPathStep {
  /// Creates the step of [runner]'s run.
  FastPathStep(
    this.runner,
    this._state,
    this._privacy,
    this._control,
    this._tools,
    this._fixed,
  );

  /// The runner (matcher, callbacks).
  final RunConfig runner;
  final RunState _state;
  final PrivacyScope _privacy;
  final RunControl _control;
  final ToolRound _tools;
  final FixedAnswer _fixed;

  /// The terminal event if the request was answered by the fast path, else
  /// `null` (the loop goes on with the model).
  Future<AgentDone?> tryRun(UserInput input) async {
    final fast = runner.fastPath;
    if (fast == null || input.images.isNotEmpty) return null;
    final confidence = input.sttConfidence;
    if (confidence != null && confidence < fastPathMinConfidence) return null;
    // The routed text is the user's text; a stripped trigger means a
    // request for a target, not a simple command.
    final routed = _state.current.effectiveText;
    if (routed != null && routed != input.text) return null;
    final language = input.language ?? input.interfaceLanguage;
    FastPathCall? call;
    try {
      call = await fast.match(input.text, language: language);
    } on Object {
      return null;
    }
    _control.throwIfAborted();
    if (call == null) return null;
    if (_privacy.catalog.lookup(call.tool) is! FixedConfirmationTool) {
      return null;
    }
    final (assistant, calls) = _tools.assignCallIds([
      ToolCallBlock(
        id: 'fast_path',
        name: call.tool,
        argumentsJson: jsonEncode(call.arguments),
      ),
    ]);
    await _state.append(assistant);
    final round = await _tools.execute(calls, null);
    final sentence = _fixed.sentenceFor(round, language);
    if (sentence != null) {
      final done = await _fixed.finish(round, sentence);
      _control.throwIfAborted();
      if (done != null) {
        runner.onFastPath?.call(runner.sessionId, call.tool);
        return done;
      }
      return null;
    }
    await _tools.verify(round);
    await _state.append(Message.toolResults(_tools.resultsOf(round)));
    _control.throwIfAborted();
    return null;
  }
}
