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
    this.name,
  });

  /// Provider profile id.
  final String profileId;

  /// Model id sent in `ChatRequest.model`.
  final String modelId;

  /// The adapter.
  final LlmProvider provider;

  /// Data-protection level of the profile.
  final PrivacyLevel privacy;

  /// Name of the profile for messages; `null` = [profileId].
  final String? name;

  /// The name shown in messages („Claude ist gerade nicht erreichbar.“).
  String get displayName => name ?? profileId;

  @override
  String toString() => 'ProviderTarget($profileId, $modelId, ${privacy.name})';
}

/// A target the user named that cannot be used.
@immutable
final class UnavailableTarget {
  /// Creates the marker.
  const UnavailableTarget(this.name, this.reason);

  /// Name of the profile for messages.
  final String name;

  /// `missing`, `disabled` or `incomplete` (no adapter).
  final String reason;

  @override
  String toString() => 'UnavailableTarget($name, $reason)';
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
    this.unavailable,
  });

  /// Chosen provider and model.
  final ProviderTarget target;

  /// Why (rule name, „Standard“, „Eskalation“ …).
  final String reason;

  /// Set when the request was routed privately: a target the user asks for
  /// („nochmal mit …“) must offer at least this level unless the user
  /// consents.
  final PrivacyLevel? privacyFloor;

  /// The user text to send to the model instead of `UserInput.text`, e.g.
  /// with the routing trigger removed (`stripTrigger`); `null` = unchanged.
  /// The stored and displayed text always stays the original.
  final String? effectiveText;

  /// The user named another target („nochmal mit Claude“): the agent hands
  /// over right away (same privacy check). Only this ever changes the
  /// provider of a run (K28).
  final ProviderTarget? requestedTarget;

  /// The user named a target („nochmal mit X“, prefix „X, …“) that is
  /// disabled or incomplete: the run ends with the reason; [target] is not
  /// used and nothing else answers instead (K28).
  final UnavailableTarget? unavailable;

  /// This resolution with [floor] as [privacyFloor].
  Resolution withPrivacyFloor(PrivacyLevel? floor) => Resolution(
    target: target,
    reason: reason,
    privacyFloor: floor,
    effectiveText: effectiveText,
    requestedTarget: requestedTarget,
    unavailable: unavailable,
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

/// Chooses the provider for a request (concept: „Routing“, K28). The
/// provider of a run only changes when the user asks for it.
abstract interface class ProviderResolver {
  /// The provider for [input] before the run starts.
  Resolution resolve(UserInput input);

  /// The target the user asked for in [current] ([Resolution.requestedTarget],
  /// „nochmal mit Claude“), or `null` if there is none. Never called for
  /// errors: Wendelin does not switch providers on its own.
  ///
  /// Privacy boundary: a target below [Resolution.privacyFloor] is returned
  /// with [Resolution.belowPrivacyFloor] true so the agent asks the user.
  Resolution? escalate(Resolution current, EscalationReason reason);
}

/// M1 resolver: everything goes to [defaultTarget]; it has no „nochmal mit“
/// targets. The rule engine ([RuleBasedResolver]) is the real one.
final class DefaultProviderResolver implements ProviderResolver {
  /// Creates the resolver. [isPrivate] marks requests as privately routed
  /// (e.g. keyword „privat“); their privacy floor is the level of
  /// [defaultTarget].
  DefaultProviderResolver(this.defaultTarget, {this.isPrivate});

  /// Target of every request.
  final ProviderTarget defaultTarget;

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
  Resolution? escalate(Resolution current, EscalationReason reason) => null;
}
