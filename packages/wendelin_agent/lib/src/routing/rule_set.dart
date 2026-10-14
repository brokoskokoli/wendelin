import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import 'conditions.dart';

const _strings = ListEquality<String>();

/// A provider profile plus model, by id only (no adapter, no secrets).
@immutable
final class RouteTarget {
  /// Creates a target.
  const RouteTarget({required this.profileId, required this.modelId});

  /// Provider profile id.
  final String profileId;

  /// Model id.
  final String modelId;

  @override
  bool operator ==(Object other) =>
      other is RouteTarget &&
      other.profileId == profileId &&
      other.modelId == modelId;

  @override
  int get hashCode => Object.hash(profileId, modelId);

  @override
  String toString() => '$profileId/$modelId';
}

/// One routing rule (concept: „Regeln vor dem Start“). The position in
/// [RuleSet.rules] is the priority.
@immutable
final class RoutingRule {
  /// Creates a rule; [aliases] are copied.
  RoutingRule({
    required this.id,
    required this.name,
    required this.condition,
    required this.target,
    this.enabled = true,
    this.stripTrigger = false,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases);

  /// Stable id (for the editor and JSON).
  final String id;

  /// Display name; becomes `Resolution.reason` and lands in the audit log.
  final String name;

  /// Whether the rule takes part.
  final bool enabled;

  /// When the rule applies.
  final Condition condition;

  /// Where matching requests go.
  final RouteTarget target;

  /// Remove the triggering prefix/keyword from the text sent to the model
  /// (the stored and displayed text stays as entered).
  final bool stripTrigger;

  /// Extra names for „nochmal mit …“ besides the rule's prefix/keyword
  /// words.
  final List<String> aliases;

  /// Whether a match makes the route private (K8 d).
  bool get isPrivate => condition.marksPrivate;

  /// Copy with changes.
  RoutingRule copyWith({
    String? id,
    String? name,
    bool? enabled,
    Condition? condition,
    RouteTarget? target,
    bool? stripTrigger,
    List<String>? aliases,
  }) => RoutingRule(
    id: id ?? this.id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    condition: condition ?? this.condition,
    target: target ?? this.target,
    stripTrigger: stripTrigger ?? this.stripTrigger,
    aliases: aliases ?? this.aliases,
  );

  @override
  bool operator ==(Object other) =>
      other is RoutingRule &&
      other.id == id &&
      other.name == name &&
      other.enabled == enabled &&
      other.condition == condition &&
      other.target == target &&
      other.stripTrigger == stripTrigger &&
      _strings.equals(other.aliases, aliases);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    enabled,
    condition,
    target,
    stripTrigger,
    _strings.hash(aliases),
  );

  @override
  String toString() => 'RoutingRule($id, $name → $target)';
}

/// The complete routing configuration: ordered [rules] (first match wins),
/// and the fixed default at the end. Escalation chains no longer exist (K28);
/// saved ones are ignored on load.
@immutable
final class RuleSet {
  /// Creates a rule set; collections are copied.
  RuleSet({List<RoutingRule> rules = const [], required this.defaultTarget})
    : rules = List.unmodifiable(rules);

  /// Reason of a request no rule matched.
  static const defaultReason = 'Standard';

  /// Rules by priority.
  final List<RoutingRule> rules;

  /// Target when no rule matches.
  final RouteTarget defaultTarget;

  /// Copy with changes.
  RuleSet copyWith({List<RoutingRule>? rules, RouteTarget? defaultTarget}) =>
      RuleSet(
        rules: rules ?? this.rules,
        defaultTarget: defaultTarget ?? this.defaultTarget,
      );

  @override
  bool operator ==(Object other) =>
      other is RuleSet &&
      const ListEquality<RoutingRule>().equals(other.rules, rules) &&
      other.defaultTarget == defaultTarget;

  @override
  int get hashCode =>
      Object.hash(const ListEquality<RoutingRule>().hash(rules), defaultTarget);
}

/// A provider profile as the router knows it: for availability, privacy
/// checks and „nochmal mit Name“. The adapter is optional so the rule
/// editor can explain and validate without building providers.
@immutable
final class RoutingProfile {
  /// Creates a profile; [aliases] are copied.
  RoutingProfile({
    required this.id,
    required this.name,
    required this.privacy,
    required this.defaultModel,
    this.enabled = true,
    this.provider,
    List<String> aliases = const [],
  }) : aliases = List.unmodifiable(aliases);

  /// Profile id.
  final String id;

  /// Display name („Claude API“).
  final String name;

  /// Data-protection level.
  final PrivacyLevel privacy;

  /// Model used when the profile is named directly („nochmal mit …“).
  final String defaultModel;

  /// Whether the profile is active.
  final bool enabled;

  /// The adapter; `null` if it cannot be built (the profile then cannot
  /// answer, rules to it are skipped).
  final LlmProvider? provider;

  /// Extra spoken names („Sonnet“).
  final List<String> aliases;

  @override
  String toString() => 'RoutingProfile($id, ${privacy.name})';
}
