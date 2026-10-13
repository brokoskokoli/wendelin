import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// One provider/model the agent can talk to.
@immutable
final class ProviderTarget {
  /// Creates a target.
  const ProviderTarget({
    required this.profileId,
    required this.modelId,
    required this.provider,
    required this.privacy,
  });

  /// Provider profile id.
  final String profileId;

  /// Model id sent in `ChatRequest.model`.
  final String modelId;

  /// The adapter.
  final LlmProvider provider;

  /// Data-protection level of the profile.
  final PrivacyLevel privacy;

  @override
  String toString() => 'ProviderTarget($profileId, $modelId, ${privacy.name})';
}

/// Where a request goes: the chosen [target] plus why, and the privacy floor
/// of the request.
@immutable
final class Resolution {
  /// Creates a resolution.
  const Resolution({
    required this.target,
    required this.reason,
    this.privacyFloor,
    this.effectiveText,
    this.requestedTarget,
    this.routeProfileId,
  });

  /// Chosen provider and model.
  final ProviderTarget target;

  /// Why (rule name, „Standard“, „Eskalation“ …).
  final String reason;

  /// Set when the request was routed privately: escalation targets must
  /// offer at least this level unless the user consents.
  final PrivacyLevel? privacyFloor;

  /// The user text to send to the model instead of `UserInput.text`, e.g.
  /// with the routing trigger removed (`stripTrigger`); `null` = unchanged.
  /// The stored and displayed text always stays the original.
  final String? effectiveText;

  /// The user named an escalation target („nochmal mit Claude“): the agent
  /// escalates right away, and the resolver goes to this target instead of
  /// the next chain link (same privacy check).
  final ProviderTarget? requestedTarget;

  /// Profile whose escalation chain applies; `null` = the target's profile.
  /// Stays the same across escalations.
  final String? routeProfileId;

  /// This resolution with [floor] as [privacyFloor].
  Resolution withPrivacyFloor(PrivacyLevel? floor) => Resolution(
    target: target,
    reason: reason,
    privacyFloor: floor,
    effectiveText: effectiveText,
    requestedTarget: requestedTarget,
    routeProfileId: routeProfileId,
  );

  /// Provider profile id.
  String get profileId => target.profileId;

  /// Model id.
  String get modelId => target.modelId;

  /// The adapter.
  LlmProvider get provider => target.provider;

  /// Data-protection level of the target.
  PrivacyLevel get privacy => target.privacy;

  /// Whether [target] is below [privacyFloor]; the agent then needs the
  /// user's consent (`EscalationConfirmationRequired`) before sending
  /// anything to it.
  bool get belowPrivacyFloor =>
      privacyFloor != null && !privacy.isAtLeast(privacyFloor!);

  @override
  String toString() => 'Resolution($target, $reason, floor: $privacyFloor)';
}

/// Chooses the provider for a request and the next one when escalating
/// (concept: „Routing und Eskalation“).
abstract interface class ProviderResolver {
  /// The provider for [input] before the run starts.
  Resolution resolve(UserInput input);

  /// The next link of the escalation chain after [current], or `null` if
  /// there is none.
  ///
  /// Privacy boundary: for a privately routed request ([Resolution.
  /// privacyFloor] set) targets with at least that level are preferred. A
  /// target below it is only returned if no compliant one is left, and then
  /// with [Resolution.belowPrivacyFloor] true so the agent asks the user.
  Resolution? escalate(Resolution current, EscalationReason reason);
}

/// M1 resolver: everything goes to [defaultTarget]; escalation walks
/// [chain] in order. The rule engine follows in M3.
final class DefaultProviderResolver implements ProviderResolver {
  /// Creates the resolver. [isPrivate] marks requests as privately routed
  /// (e.g. keyword „privat“); their privacy floor is the level of
  /// [defaultTarget].
  DefaultProviderResolver(
    this.defaultTarget,
    List<ProviderTarget> chain, {
    this.isPrivate,
  }) : chain = List.unmodifiable(chain);

  /// Target of every request.
  final ProviderTarget defaultTarget;

  /// Escalation chain after [defaultTarget], weakest first.
  final List<ProviderTarget> chain;

  /// Whether a request is private; `null` = never.
  final bool Function(UserInput input)? isPrivate;

  @override
  Resolution resolve(UserInput input) {
    final private = isPrivate?.call(input) ?? false;
    return Resolution(
      target: defaultTarget,
      reason: private ? 'Privat' : 'Standard',
      privacyFloor: private ? defaultTarget.privacy : null,
    );
  }

  @override
  Resolution? escalate(Resolution current, EscalationReason reason) {
    final all = [defaultTarget, ...chain];
    final index = all.indexWhere(
      (t) => t.profileId == current.profileId && t.modelId == current.modelId,
    );
    final remaining = all
        .skip(index + 1)
        .where(
          (t) =>
              t.profileId != current.profileId || t.modelId != current.modelId,
        )
        .toList();
    if (remaining.isEmpty) return null;
    final floor = current.privacyFloor;
    final next = floor == null
        ? remaining.first
        : remaining.firstWhere(
            (t) => t.privacy.isAtLeast(floor),
            orElse: () => remaining.first,
          );
    return Resolution(
      target: next,
      reason: 'Eskalation: ${reason.name}',
      privacyFloor: floor,
    );
  }
}
