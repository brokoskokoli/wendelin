/// Start of one agent run (concept: „Agent-Schleife“, step 1; ADR 0009 §3
/// and §4): routing, context, the privacy floor of a repeated turn, the
/// recorded user message and the text the model gets. Internal to
/// `wendelin_agent`, not exported.
library;

import 'package:collection/collection.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../agent_runner_texts.dart';
import 'privacy_scope.dart';
import 'run_config.dart';
import 'run_state.dart';

/// Routes [input], builds the context into [state] and records the user
/// message. Returns whether the user asked to repeat the previous turn
/// („nochmal mit …“ or [UserInput.requestEscalation]); throws [RunStop]
/// when a private request has no target of enough privacy.
///
/// Invariants: a repeated turn inherits the previous turn's floor (K8 d),
/// the floor follows the taint before the user message is recorded, and
/// a private request without a sufficient target is never sent.
Future<bool> startRun(
  RunConfig runner,
  UserInput input,
  RunState state,
  PrivacyScope privacy,
  RunControl control,
) async {
  state.current = runner.resolver.resolve(input);
  control.emit(
    Routed(
      profileId: state.current.profileId,
      modelId: state.current.modelId,
      reason: state.current.reason,
    ),
  );
  state.context = await runner.contextBuilder.build(input);
  state.messages.addAll(state.context.messages);
  // A private request without any target of enough privacy is not sent.
  final noPrivateTarget = state.current.belowPrivacyFloor;
  final retry =
      input.requestEscalation || state.current.requestedTarget != null;
  if (retry) {
    // „nochmal mit …“ repeats the previous turn: its privacy floor applies
    // to this run too (K8 d).
    final previous = state.context.messages
        .take(state.context.messages.length - 1)
        .lastWhereOrNull((m) => m.role == Role.user)
        ?.privacyFloor;
    if (previous != null) state.raiseFloor(previous);
  }
  privacy.raiseFloorToTaint();
  await state.record(state.context.messages.last);
  if (noPrivateTarget) {
    throw RunStop(
      const AgentFailed(
        error: AgentErrorKind.provider,
        message: AgentRunnerTexts.noPrivateTarget,
      ),
    );
  }
  // The model gets the routed text (trigger stripped); the recorded and
  // displayed message stays as the user said it.
  if (state.current.effectiveText case final text?) {
    state.messages.last = Message.user(text, images: input.images);
  }
  return retry;
}
