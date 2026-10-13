/// Escalation of one agent run (concept: „Routing und Eskalation“, K8 d,
/// K10 c, ADR 0009): asks the resolver for the next target, asks the user
/// before handing private or protected data to a weaker target, and hands
/// the run over. Internal to `wendelin_agent`, not exported.
library;

import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../agent_runner_texts.dart';
import '../provider_resolver.dart';
import 'privacy_scope.dart';
import 'run_budget.dart';
import 'run_state.dart';

/// Hands a run to the next target of the resolver's chain.
///
/// Invariants:
/// - Below the privacy floor or with protected results on board, the user
///   is asked first. A „no“ below the floor stands for the whole run (no
///   second question); a „no“ to protected data ends the run.
/// - A hand-over resets the per-provider counters of the [RunBudget] and
///   drops the previous provider's paused answer, streamed text
///   (`AgentTextReset`), signed thinking and foreign provider blocks.
final class Escalation {
  /// Creates the escalation of one run.
  Escalation(
    this._resolver,
    this._state,
    this._privacy,
    this._budget,
    this._control,
  );

  final ProviderResolver _resolver;
  final RunState _state;
  final PrivacyScope _privacy;
  final RunBudget _budget;
  final RunControl _control;

  /// Tries to hand the request to the next provider; returns whether it
  /// happened.
  Future<bool> escalate(EscalationReason reason) async {
    final current = _state.current;
    final next = _resolver.escalate(current, reason);
    if (next == null) return false;
    final same =
        next.profileId == current.profileId && next.modelId == current.modelId;
    // Results of tools the next target may not see are in this run: it
    // gets them redacted, but the user decides whether to hand over at all.
    final protectedData = _privacy.holdsProtectedFor(next);
    if (next.belowPrivacyFloor || protectedData) {
      if (!await _consent(next, reason, protectedData: protectedData)) {
        return false;
      }
    }
    if (same) {
      // Retry on the same target („nochmal mit <aktuelles Ziel>“): nothing
      // to hand over, only the consent above may have been needed.
      _state.current = next;
      return true;
    }
    _handOver(next, reason);
    return true;
  }

  /// Asks the user whether [next] may get this run; throws [RunStop] when
  /// protected data is declined.
  Future<bool> _consent(
    Resolution next,
    EscalationReason reason, {
    required bool protectedData,
  }) async {
    // Ask at most once per run; a „no“ stands.
    if (_privacy.consentDeclined && !protectedData) return false;
    final answer = Completer<bool>();
    final question = EscalationConfirmationRequired(
      fromProfile: _state.current.profileId,
      toProfile: next.profileId,
      reason: reason,
      respond: answer.complete,
    );
    _control.emit(question);
    final approved = await Future.any([
      answer.future,
      _control.token.whenCancelled.then((_) => false),
    ]);
    question.respond(false); // no-op if answered
    // An abort while the question was open wins over the answer.
    _control.throwIfAborted();
    if (approved) {
      _privacy.consented(belowFloor: next.belowPrivacyFloor);
      return true;
    }
    if (protectedData) {
      throw RunStop(
        const AgentFailed(
          error: AgentErrorKind.provider,
          message: AgentRunnerTexts.protectedDeclined,
        ),
      );
    }
    _privacy.declined();
    return false;
  }

  /// Switches the run to [next] (another target).
  void _handOver(Resolution next, EscalationReason reason) {
    _control.emit(
      Escalated(
        fromProfile: _state.current.profileId,
        toProfile: next.profileId,
        reason: reason,
      ),
    );
    // The answer of the previous provider is discarded: paused segments and
    // streamed text of the current call.
    final paused = _state.paused;
    _state.messages.removeWhere((m) => paused.any((p) => identical(p, m)));
    paused.clear();
    if (_control.segmentStreamed) {
      _control.emit(const AgentTextReset('An anderes Modell übergeben'));
    }
    _state.current = next;
    _state.epoch++;
    // Invariant: counters per provider start fresh at the new provider.
    _budget.onEscalated();
    _dropForeignBlocks();
  }

  /// Signed thinking belongs to the provider that produced it; provider
  /// blocks only make sense for their provider family.
  void _dropForeignBlocks() {
    final family = _state.current.provider.type.name;
    bool foreign(ContentBlock b) =>
        b is ThinkingBlock || (b is ProviderBlock && b.provider != family);
    final messages = _state.messages;
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.content.any(foreign)) {
        messages[i] = Message(m.role, [
          for (final b in m.content)
            if (!foreign(b)) b,
        ]);
      }
    }
  }
}
