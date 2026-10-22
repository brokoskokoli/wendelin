/// Offer „Mit X nochmal?“ after a provider failure (WP128, concept K28):
/// proposes another configured provider with at least the privacy level of
/// the failed one and hands the run over only if the user says yes. Only the
/// model call is repeated; the conversation (with the results of tools that
/// already ran) stays as it is, so tools never run twice. Internal to
/// `wendelin_agent`, not exported.
library;

import 'dart:async';

import 'package:wendelin_core/wendelin_core.dart';

import '../provider_resolver.dart';
import 'escalation.dart';
import 'run_config.dart';
import 'run_state.dart';

/// Asks the user whether a failed model call may be repeated elsewhere.
///
/// Invariants:
/// - Offered only for failures of the provider (timeout, network, 5xx, TEE
///   check): never for a cancel, a budget stop, a rejected request or
///   missing credentials ([offerable]).
/// - The offered target is another configured profile whose privacy level is
///   at least the failed one's and at least the run's privacy floor
///   ([candidate]); a private run never goes to a
///   weaker (cloud) target. Without such a target there is no offer.
/// - Nothing is handed over before a „yes“; a profile is offered at most
///   once per run and a failed target is never offered again.
final class RetryOffer {
  /// Creates the offer logic of one run.
  RetryOffer(this._config, this._state, this._escalation, this._control);

  final RunConfig _config;
  final RunState _state;
  final Escalation _escalation;
  final RunControl _control;

  /// Profiles that already failed or were offered in this run.
  final Set<String> _used = {};

  /// Whether [error] is a failure of the provider that may be offered a
  /// retry elsewhere.
  static bool offerable(ProviderException error) => switch (error) {
    ProviderTimeoutException() || NetworkException() => true,
    // The GPU check has its own dialog („Ohne GPU-Prüfung senden“).
    AttestationFailedException(:final stage) => stage != 'gpu',
    ServerException(:final statusCode) => statusCode >= 500,
    _ => false,
  };

  /// The target to offer for [error], or `null` (no offer).
  ProviderTarget? candidate(ProviderException error) {
    if (!offerable(error)) return null;
    final current = _state.current;
    final targets = _config.fallbackTargets?.call() ?? const [];
    // A private run keeps its floor even after an approved escalation to a
    // weaker target: the next offer must not be below it either.
    final floor = current.privacyFloor;
    final required = floor != null && floor.isAtLeast(current.privacy)
        ? floor
        : current.privacy;
    for (final t in targets) {
      if (t.profileId == current.profileId || _used.contains(t.profileId)) {
        continue;
      }
      if (t.privacy.isAtLeast(required)) return t;
    }
    return null;
  }

  /// Asks the user and, on „yes“, hands the run to the offered target.
  /// Returns whether the run goes on there; throws `RunStop` on an abort.
  Future<bool> offer(ProviderException error, ProviderTarget target) async {
    _used
      ..add(_state.current.profileId)
      ..add(target.profileId);
    final answer = Completer<bool>();
    final question = RetryOfferRequired(
      fromProfile: _state.current.profileId,
      toProfile: target.profileId,
      error: error,
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
    if (!approved) return false;
    _escalation.handOver(
      Resolution(
        target: target,
        reason: 'Nach Ausfall: ${target.displayName}',
        privacyFloor: _state.current.privacyFloor,
      ),
      EscalationReason.providerFailed,
    );
    return true;
  }
}
