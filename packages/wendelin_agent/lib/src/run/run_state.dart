/// Shared state of one agent run (`AgentRunner.run`) and the interface the
/// run's units (privacy scope, budget, escalation, tool round, model call)
/// use to talk back to the loop in `agent_runner.dart`. Internal to
/// `wendelin_agent`, not exported.
library;

import 'package:wendelin_core/wendelin_core.dart';

import '../agent_config.dart';
import '../context_builder.dart';
import '../ports.dart';
import '../provider_resolver.dart';

/// An executed tool call.
typedef Executed = ({ToolCallBlock call, ToolOutcome outcome});

/// Whether [o] is the user's „no“ to a confirmation (the tool did not run).
bool isDeclined(ToolOutcome o) =>
    !o.isError && o.text == ToolOutcome.declinedText;

/// A run ended early (abort or limit); carries the terminal event.
final class RunStop implements Exception {
  /// Creates the stop with its terminal [event].
  RunStop(this.event);

  /// The terminal event of the run.
  final AgentFailed event;
}

/// What the units of a run need from the loop: event output, the cancel
/// token and the abort check.
abstract interface class RunControl {
  /// Cancelled when the run is aborted.
  CancelToken get token;

  /// Whether text was streamed in the current segment, i.e. since the last
  /// tool event or text reset (the scope of `AgentTextReset`).
  bool get segmentStreamed;

  /// Sends [e] to the listener (no-op once the stream is closed).
  void emit(AgentEvent e);

  /// Throws [RunStop] with the abort event if the run was aborted. Units
  /// call it after every await that may outlast an abort, so an abort wins
  /// over whatever happened meanwhile.
  void throwIfAborted();
}

/// The conversation state of one run: target, context, the messages as the
/// model sees them, the paused answer and the executed tool calls.
///
/// Invariant: the privacy floor of [current] never sinks during a run.
/// Only [raiseFloor] sets it here, and escalations take the floor along
/// (the resolver carries it over, K8 d).
final class RunState {
  /// Creates the state; [recorder] persists kept messages.
  RunState(this.recorder);

  /// Persists the conversation; `null` = not persisted.
  final ConversationRecorder? recorder;

  /// The current target with the run's privacy floor.
  late Resolution current;

  /// The context built for this run.
  late final AgentContext context;

  /// The conversation as sent to the model (before redaction per target).
  final List<Message> messages = [];

  /// Assistant messages of a paused turn (`StopReason.pauseTurn`), not yet
  /// recorded.
  final List<Message> paused = [];

  /// Tool calls executed in this run.
  final List<Executed> executed = [];

  /// Whether a result that is not explicitly trusted ([isTrustedResult])
  /// is in the conversation: from the history (set at the start) or from
  /// this run. From then on the `<spoken>` block is off (WP41): the user
  /// cannot see what injected text would make the assistant say.
  bool untrustedSeen = false;

  /// Language of the request (for the spoken-text check); `null` = unknown.
  String? language;

  /// The protection level of the spoken text (WP55), set at the start.
  SpokenVersion spokenVersion = SpokenVersion.off;

  /// The speech style the next model call uses: with
  /// [SpokenVersion.protected], stage 2 falls back to stage 1 once
  /// [untrustedSeen]; `always` and `checked` keep asking for the block.
  SpeechStyle get speech =>
      untrustedSeen &&
          spokenVersion == SpokenVersion.protected &&
          context.speech == SpeechStyle.twoVersions
      ? SpeechStyle.hint
      : context.speech;

  /// Whether the first model call of the run has started. A target change
  /// („nochmal mit X“) only happens before it (K28).
  bool modelCalled = false;

  /// Raises the run's privacy floor to [floor]; never lowers it.
  void raiseFloor(PrivacyLevel floor) {
    final own = current.privacyFloor;
    // Invariant: the floor only rises (a lower [floor] changes nothing).
    if (own == null || !own.isAtLeast(floor)) {
      current = current.withPrivacyFloor(floor);
    }
  }

  /// Adds a kept message; records paused segments of this answer first.
  Future<void> append(Message m) async {
    for (final p in paused) {
      await record(p);
    }
    paused.clear();
    messages.add(m);
    await record(m);
  }

  /// Records [m]; messages of a private run carry its privacy floor so
  /// later turns can hide them from weaker targets.
  Future<void> record(Message m) async {
    final floor = current.privacyFloor;
    await recorder?.record(floor == null ? m : m.withPrivacyFloor(floor));
  }
}

/// The terminal event for a run that ended with [kind] under [config].
AgentFailed failedEvent(AgentErrorKind kind, AgentConfig config) => AgentFailed(
  error: kind,
  message: switch (kind) {
    AgentErrorKind.cancelled => 'Abgebrochen.',
    AgentErrorKind.timeout =>
      'Das hat zu lange gedauert, ich habe nach '
          '${config.maxDuration.inSeconds} Sekunden abgebrochen.',
    AgentErrorKind.toolRoundLimit =>
      'Ich bin nach ${config.maxToolRounds} Tool-Runden zu keinem '
          'Ergebnis gekommen und habe abgebrochen.',
    AgentErrorKind.tokenBudget =>
      'Das Token-Budget für diese Anfrage ist aufgebraucht.',
    AgentErrorKind.budgetBlocked =>
      'Das Monatsbudget für diesen Anbieter ist erreicht.',
    AgentErrorKind.provider => 'Der Anbieter ist nicht erreichbar.',
    AgentErrorKind.internal => 'Interner Fehler im Agenten.',
  },
);
