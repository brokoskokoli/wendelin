import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// What the tool runtime does with a call.
enum PolicyAction {
  /// Execute without asking.
  allow,

  /// Ask the user first.
  confirm,

  /// Do not execute.
  deny;

  /// The stricter of this and [other] (`allow` < `confirm` < `deny`).
  PolicyAction atLeast(PolicyAction other) =>
      index >= other.index ? this : other;
}

/// Outcome of [RiskPolicy.decide].
@immutable
final class PolicyDecision {
  const PolicyDecision._(this.action, [this.reason]);

  /// Execute without asking.
  static const allow = PolicyDecision._(PolicyAction.allow);

  /// Ask the user first.
  static const confirm = PolicyDecision._(PolicyAction.confirm);

  /// Do not execute; [reason] is a German text for the model.
  factory PolicyDecision.deny(String reason) =>
      PolicyDecision._(PolicyAction.deny, reason);

  /// The decided action.
  final PolicyAction action;

  /// Why the call is denied (only for [PolicyAction.deny]).
  final String? reason;

  @override
  bool operator ==(Object other) =>
      other is PolicyDecision &&
      other.action == action &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(action, reason);

  @override
  String toString() =>
      'PolicyDecision(${action.name}${reason == null ? '' : ': $reason'})';
}

/// Decides per call whether a tool runs freely, needs confirmation or is
/// denied.
///
/// Defaults per [RiskLevel]: `read` and `write` run freely (write tools offer
/// undo), `external` is always confirmed. Overrides per tool can only make a
/// tool **stricter**: an override is combined with the default by taking the
/// stricter action, so an `external` tool can never run without
/// confirmation, whatever is configured. After [lockExternal] every
/// `external` tool of that session is denied.
final class RiskPolicy {
  /// Creates a policy with optional per-tool [overrides].
  RiskPolicy({Map<String, PolicyAction> overrides = const {}})
    : _overrides = Map.of(overrides);

  final Map<String, PolicyAction> _overrides;
  final Set<String> _lockedSessions = {};

  /// Default action for a risk level.
  static PolicyAction defaultFor(RiskLevel risk) => switch (risk) {
    RiskLevel.read || RiskLevel.write => PolicyAction.allow,
    RiskLevel.external => PolicyAction.confirm,
  };

  /// Text given to the model when external tools are locked.
  static const lockedReason =
      'Aktionen mit Außenwirkung sind in dieser Sitzung gesperrt, weil die '
      'Antwort des Anbieters nicht verifiziert werden konnte.';

  /// Text given to the model when the user disabled a tool by override.
  static const deniedReason = 'Dieses Tool ist vom Nutzer gesperrt.';

  /// Sets the override for [toolName]; it can only tighten the default
  /// (an `allow` override on an `external` tool has no effect).
  void setOverride(String toolName, PolicyAction action) =>
      _overrides[toolName] = action;

  /// Removes the override for [toolName].
  void clearOverride(String toolName) => _overrides.remove(toolName);

  /// The configured override for [toolName], if any.
  PolicyAction? overrideFor(String toolName) => _overrides[toolName];

  /// Denies every `external` tool for [sessionId] from now on (e.g. after a
  /// failed TEE receipt check). There is no unlock: the lock lasts for the
  /// rest of the session.
  void lockExternal(String sessionId) => _lockedSessions.add(sessionId);

  /// Whether [lockExternal] was called for [sessionId].
  bool isExternalLocked(String sessionId) =>
      _lockedSessions.contains(sessionId);

  /// The decision for running [tool] in [sessionId].
  PolicyDecision decide(Tool tool, String sessionId) {
    if (tool.risk == RiskLevel.external && isExternalLocked(sessionId)) {
      return PolicyDecision.deny(lockedReason);
    }
    final base = defaultFor(tool.risk);
    final override = _overrides[tool.name];
    final action = override == null ? base : base.atLeast(override);
    return switch (action) {
      PolicyAction.allow => PolicyDecision.allow,
      PolicyAction.confirm => PolicyDecision.confirm,
      PolicyAction.deny => PolicyDecision.deny(deniedReason),
    };
  }
}
