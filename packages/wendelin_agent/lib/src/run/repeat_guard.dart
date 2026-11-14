/// Repetition of failed tool calls within one run (WP150, WP200). Internal
/// to `wendelin_agent`, not exported.
library;

import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../agent_runner_texts.dart';
import 'run_state.dart';

/// Whether [a] and [b] call the same tool with equal arguments.
bool sameContent(ToolCallBlock a, ToolCallBlock b) {
  if (a.name != b.name) return false;
  final args = b.tryDecodeArguments();
  return args == null
      ? a.argumentsJson == b.argumentsJson
      : const DeepCollectionEquality().equals(a.tryDecodeArguments(), args);
}

/// The text blocks of [o], joined and trimmed.
String _textOf(ToolOutcome o) =>
    o.content.whereType<TextBlock>().map((b) => b.text).join(' ').trim();

/// Blocks the repetition of a call that just failed and counts the vain
/// repetitions of a run.
final class RepeatGuard {
  /// Creates the guard of the run with [_state].
  RepeatGuard(this._state);

  final RunState _state;

  /// How often the same failing call (same tool, same arguments, error each
  /// time) may be sent before the run stops with that error. The first
  /// repetition of a failed call is not executed (the model gets the error
  /// and a hint, [blockedOutcome]), the second one ends the run before it is
  /// executed: 1 execution + 2 repetitions. Only calls of one round can
  /// still be executed more than once.
  static const maxSameFailures = 3;

  /// The error result for [call] if the same tool with the same arguments
  /// already failed in this run (it never reaches the invoker, so there is
  /// no second confirmation), else `null`. A declined call is no error; a
  /// cancelled one does not count as a failure of the call.
  ToolOutcome? blockedOutcome(ToolCallBlock call) {
    Executed? failed;
    for (final e in _state.executed) {
      if (e.outcome.isError &&
          e.outcome.text != ToolOutcome.cancelledText &&
          sameContent(e.call, call)) {
        failed = e;
      }
    }
    if (failed == null) return null;
    _state.blockedRepeats.add(call);
    return ToolOutcome.error(
      AgentRunnerTexts.repeatedFailedCall(_textOf(failed.outcome)),
      summary: 'Wiederholung nicht ausgeführt',
    );
  }

  /// The tool, error text and number of a call of [calls] that failed or was
  /// sent in vain [maxSameFailures] times in this run with the same tool and
  /// arguments, or `null`. The model gets the error in every result; if it
  /// still repeats the call, the run ends instead of spinning until the
  /// round limit.
  ({String tool, String error, int count})? repeatedFailure(
    List<ToolCallBlock> calls,
  ) {
    for (final call in calls) {
      final same = [
        for (final e in _state.executed)
          if (e.outcome.isError && sameContent(e.call, call)) e,
      ];
      final blocked = _state.blockedRepeats
          .where((b) => sameContent(b, call))
          .length;
      if (same.isNotEmpty && same.length + blocked >= maxSameFailures) {
        return (
          tool: call.name,
          error: _textOf(same.last.outcome),
          count: same.length + blocked,
        );
      }
    }
    return null;
  }
}
