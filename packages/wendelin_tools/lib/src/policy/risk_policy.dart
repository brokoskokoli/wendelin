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
/// Defaults per [RiskLevel]: `read` and `write` run freely (level C, write
/// tools offer undo), `external` is confirmed (level D). The user may choose
/// a [SecurityLevel] per tool (WP154, ADR 0022, [setLevel]); the policy
/// table [levelAccess] then decides, so a level can loosen as well as
/// tighten the default. Overrides ([setOverride], e.g. a disabled tool)
/// can only tighten. After [lockExternal] every `external` tool of that
/// session is denied, whatever the level.
final class RiskPolicy {
  /// Creates a policy with optional per-tool [overrides].
  RiskPolicy({Map<String, PolicyAction> overrides = const {}})
    : _overrides = Map.of(overrides);

  final Map<String, PolicyAction> _overrides;
  final Map<String, SecurityLevel> _levels = {};
  final Set<String> _lockedSessions = {};

  /// Default security level for a risk level (the recommendation).
  static SecurityLevel defaultLevelFor(RiskLevel risk) => switch (risk) {
    RiskLevel.read || RiskLevel.write => SecurityLevel.c,
    RiskLevel.external => SecurityLevel.d,
  };

  /// Default action for a risk level.
  static PolicyAction defaultFor(RiskLevel risk) => switch (risk) {
    RiskLevel.read || RiskLevel.write => PolicyAction.allow,
    RiskLevel.external => PolicyAction.confirm,
  };

  /// The risk level a call is *treated* as: a call the policy wants
  /// confirmed counts as `external` (also a `read`/`write` tool the user made
  /// stricter), otherwise the tool's own [risk]. Shown on the confirmation
  /// card instead of `Tool.risk`.
  static RiskLevel effectiveRisk(RiskLevel risk, PolicyAction action) =>
      action == PolicyAction.confirm ? RiskLevel.external : risk;

  /// Text given to the model when external tools are locked.
  static const lockedReason =
      'Aktionen mit Außenwirkung sind in dieser Sitzung gesperrt, weil die '
      'Antwort des Anbieters nicht verifiziert werden konnte.';

  /// Text given to the model when the user disabled a tool by override.
  static const deniedReason = 'Dieses Tool ist vom Nutzer gesperrt.';

  /// Sets the override for [toolName]; it can only tighten the result of
  /// the default or the chosen level.
  void setOverride(String toolName, PolicyAction action) =>
      _overrides[toolName] = action;

  /// Removes the override for [toolName].
  void clearOverride(String toolName) => _overrides.remove(toolName);

  /// Sets the security level the user chose for [toolName].
  void setLevel(String toolName, SecurityLevel level) =>
      _levels[toolName] = level;

  /// Removes the chosen level of [toolName] (back to the default).
  void clearLevel(String toolName) => _levels.remove(toolName);

  /// The chosen level of [toolName], if any.
  SecurityLevel? levelFor(String toolName) => _levels[toolName];

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
    final level = _levels[tool.name];
    // The recipient is not locked and no voice is involved yet (WP154 L1).
    final base = level == null
        ? defaultFor(tool.risk)
        : switch (levelAccess(level)) {
            LevelAccess.allowed => PolicyAction.allow,
            LevelAccess.confirm || LevelAccess.unlock => PolicyAction.confirm,
          };
    final override = _overrides[tool.name];
    final action = override == null ? base : base.atLeast(override);
    return switch (action) {
      PolicyAction.allow => PolicyDecision.allow,
      PolicyAction.confirm => PolicyDecision.confirm,
      PolicyAction.deny => PolicyDecision.deny(deniedReason),
    };
  }
}
