import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'routing_context.dart';
import 'rule_set.dart';

/// Why a rule did not decide a request.
enum SkipReason {
  /// The rule is switched off.
  disabled,

  /// A condition cannot be evaluated (broken regex, bad time …).
  invalid,

  /// The target profile no longer exists.
  profileMissing,

  /// The target profile is switched off.
  profileDisabled,

  /// The target profile exists but its adapter cannot be built.
  profileUnavailable,

  /// The condition does not hold.
  noMatch,
}

/// A rule that was looked at before the decision and why it lost.
@immutable
final class SkippedRule {
  /// Creates the entry.
  const SkippedRule(this.rule, this.reason, [this.detail]);

  /// The rule.
  final RoutingRule rule;

  /// Why it was skipped.
  final SkipReason reason;

  /// Details, e.g. the regex error.
  final String? detail;

  @override
  String toString() => 'SkippedRule(${rule.name}, ${reason.name})';
}

/// The outcome of routing one request (see [explain]).
@immutable
final class RouteDecision {
  /// Creates a decision.
  const RouteDecision({
    required this.rule,
    required this.target,
    required this.skipped,
    this.privateMatches = const [],
    this.effectiveText,
  });

  /// The winning rule; `null` = default.
  final RoutingRule? rule;

  /// Where the request goes.
  final RouteTarget target;

  /// Rules looked at before the winner, in order, with reasons.
  final List<SkippedRule> skipped;

  /// Enabled, valid rules whose `privacy` condition matched – anywhere in
  /// the list, before or after the winner and even if their target is not
  /// available (ADR 0009 §4). The resolver derives the privacy floor from
  /// them.
  final List<RoutingRule> privateMatches;

  /// Whether the request is private (a `privacy` condition matched).
  bool get private => privateMatches.isNotEmpty;

  /// The text for the model with the trigger removed (`stripTrigger`);
  /// `null` = the original text.
  final String? effectiveText;

  /// Rule name, or [RuleSet.defaultReason].
  String get reason => rule?.name ?? RuleSet.defaultReason;

  @override
  String toString() => 'RouteDecision($reason → $target)';
}

/// Which rule takes [ctx] and why the rules before it did not — the basis
/// of the editor's test field („welche Regel greift für diesen Satz?“).
///
/// With [profiles], rules whose target profile is missing or disabled are
/// skipped; without, profiles are not checked.
RouteDecision explain(
  RuleSet rules,
  RoutingContext ctx, {
  Map<String, RoutingProfile>? profiles,
}) => decideRoute(rules, ctx, profiles: profiles);

/// [explain] for the resolver: with [needProvider], profiles without an
/// adapter count as unavailable too.
RouteDecision decideRoute(
  RuleSet rules,
  RoutingContext ctx, {
  Map<String, RoutingProfile>? profiles,
  bool needProvider = false,
}) {
  final skipped = <SkippedRule>[];
  for (final rule in rules.rules) {
    if (!rule.enabled) {
      skipped.add(SkippedRule(rule, SkipReason.disabled));
      continue;
    }
    if (problemOf(rule) case final problem?) {
      skipped.add(SkippedRule(rule, SkipReason.invalid, problem));
      continue;
    }
    if (profiles != null) {
      final reason = profileProblem(
        profiles[rule.target.profileId],
        needProvider: needProvider,
      );
      if (reason != null) {
        skipped.add(SkippedRule(rule, reason));
        continue;
      }
    }
    final match = rule.condition.evaluate(ctx);
    if (match == null) {
      skipped.add(SkippedRule(rule, SkipReason.noMatch));
      continue;
    }
    String? effective;
    if (rule.stripTrigger && match.triggers.isNotEmpty) {
      final rest = ctx.text.without(match.triggers);
      if (rest != null && rest != ctx.input.text) effective = rest;
    }
    return RouteDecision(
      rule: rule,
      target: rule.target,
      skipped: List.unmodifiable(skipped),
      privateMatches: _privateMatches(rules, ctx, rule, match),
      effectiveText: effective,
    );
  }
  return RouteDecision(
    rule: null,
    target: rules.defaultTarget,
    skipped: List.unmodifiable(skipped),
    privateMatches: _privateMatches(rules, ctx, null, null),
  );
}

/// Privacy does not depend on rule order or target availability: every
/// enabled, valid rule with a `privacy` condition is checked.
List<RoutingRule> _privateMatches(
  RuleSet rules,
  RoutingContext ctx,
  RoutingRule? winner,
  ConditionMatch? winnerMatch,
) => List.unmodifiable([
  for (final rule in rules.rules)
    if (rule.enabled && rule.isPrivate && problemOf(rule) == null)
      if ((identical(rule, winner) ? winnerMatch : rule.condition.evaluate(ctx))
              ?.private ??
          false)
        rule,
]);

/// The first problem of a condition of [rule], or `null`.
String? problemOf(RoutingRule rule) {
  for (final c in rule.condition.all) {
    if (c.problem case final p?) return p;
  }
  return null;
}

/// Why [profile] cannot take requests, or `null` if it can.
SkipReason? profileProblem(
  RoutingProfile? profile, {
  bool needProvider = false,
}) {
  if (profile == null) return SkipReason.profileMissing;
  if (!profile.enabled) return SkipReason.profileDisabled;
  if (needProvider && profile.provider == null) {
    return SkipReason.profileUnavailable;
  }
  return null;
}

/// Kind of a [RuleSetIssue].
enum RuleSetIssueKind {
  /// A rule's condition cannot be evaluated; the rule is skipped.
  invalidCondition,

  /// Two rules share an id.
  duplicateRuleId,

  /// A rule targets a profile that does not exist; the rule is skipped.
  profileMissing,

  /// A rule targets a disabled profile; the rule is skipped.
  profileDisabled,

  /// A `privacy` rule targets a profile below `tee`.
  privacyTargetTooWeak,

  /// The default target's profile is missing or disabled.
  defaultTargetUnavailable,
}

/// A warning about a [RuleSet] (shown in the editor; routing goes on).
@immutable
final class RuleSetIssue {
  /// Creates an issue.
  const RuleSetIssue(this.kind, this.message, {this.ruleId, this.profileId});

  /// What is wrong.
  final RuleSetIssueKind kind;

  /// German text for the user.
  final String message;

  /// The rule concerned, if any.
  final String? ruleId;

  /// The profile concerned, if any.
  final String? profileId;

  @override
  bool operator ==(Object other) =>
      other is RuleSetIssue &&
      other.kind == kind &&
      other.message == message &&
      other.ruleId == ruleId &&
      other.profileId == profileId;

  @override
  int get hashCode => Object.hash(kind, message, ruleId, profileId);

  @override
  String toString() => 'RuleSetIssue(${kind.name}, $ruleId, $profileId)';
}

/// Checks [rules] against the known [profiles].
List<RuleSetIssue> validateRuleSet(
  RuleSet rules,
  Map<String, RoutingProfile> profiles,
) {
  final issues = <RuleSetIssue>[];
  final ids = <String>{};
  for (final rule in rules.rules) {
    final r = '„${rule.name}“';
    if (!ids.add(rule.id)) {
      issues.add(
        RuleSetIssue(
          RuleSetIssueKind.duplicateRuleId,
          'Regel $r: Id „${rule.id}“ ist doppelt.',
          ruleId: rule.id,
        ),
      );
    }
    if (problemOf(rule) case final p?) {
      issues.add(
        RuleSetIssue(
          RuleSetIssueKind.invalidCondition,
          'Regel $r ist ungültig und wird übersprungen: $p',
          ruleId: rule.id,
        ),
      );
    }
    final pid = rule.target.profileId;
    final profile = profiles[pid];
    if (profile == null) {
      issues.add(
        RuleSetIssue(
          RuleSetIssueKind.profileMissing,
          'Regel $r: Das Zielprofil gibt es nicht mehr, die Regel wird '
          'übersprungen.',
          ruleId: rule.id,
          profileId: pid,
        ),
      );
    } else if (!profile.enabled) {
      issues.add(
        RuleSetIssue(
          RuleSetIssueKind.profileDisabled,
          'Regel $r: Das Zielprofil „${profile.name}“ ist deaktiviert, die '
          'Regel wird übersprungen.',
          ruleId: rule.id,
          profileId: pid,
        ),
      );
    } else if (rule.isPrivate && !profile.privacy.isAtLeast(PrivacyLevel.tee)) {
      issues.add(
        RuleSetIssue(
          RuleSetIssueKind.privacyTargetTooWeak,
          'Regel $r ist privat, aber „${profile.name}“ ist weder TEE noch '
          'lokal.',
          ruleId: rule.id,
          profileId: pid,
        ),
      );
    }
  }
  if (profileProblem(profiles[rules.defaultTarget.profileId]) != null) {
    issues.add(
      RuleSetIssue(
        RuleSetIssueKind.defaultTargetUnavailable,
        'Das Standardziel ist nicht verfügbar.',
        profileId: rules.defaultTarget.profileId,
      ),
    );
  }
  return issues;
}
