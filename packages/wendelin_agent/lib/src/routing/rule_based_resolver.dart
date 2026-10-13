import 'package:wendelin_core/wendelin_core.dart';

import '../provider_resolver.dart';
import 'routing_context.dart';
import 'routing_engine.dart';
import 'routing_text.dart';
import 'rule_set.dart';
import 'tool_category_matcher.dart';

/// [ProviderResolver] with routing rules (M3, ADR 0009).
///
/// - `resolve`: the first enabled, valid rule whose condition holds and
///   whose target profile is available wins, else the default target.
///   `Resolution.reason` is the rule name. A `privacy` match sets the
///   privacy floor to the level of the rule's target (K8 d).
/// - `escalate`: walks the chain **of the routed profile**
///   (`RuleSet.chains`), skipping unavailable profiles; the floor stays.
/// - „nochmal mit Name“ (de/fr/en) with a profile name, a profile alias,
///   a rule alias or a rule's prefix/keyword word escalates directly to
///   that target.
final class RuleBasedProviderResolver implements ProviderResolver {
  /// Creates the resolver. Throws [ArgumentError] if the default target's
  /// profile is missing, disabled or has no adapter.
  RuleBasedProviderResolver({
    required this.rules,
    required Iterable<RoutingProfile> profiles,
    required this.clock,
    required this.network,
    ToolCategoryMatcher? matcher,
  }) : profiles = Map.unmodifiable({for (final p in profiles) p.id: p}),
       matcher = matcher ?? KeywordToolCategoryMatcher() {
    if (_build(rules.defaultTarget) == null) {
      throw ArgumentError.value(
        rules.defaultTarget.profileId,
        'rules.defaultTarget',
        'Standardprofil nicht verfügbar',
      );
    }
    issues = List.unmodifiable(validateRuleSet(rules, this.profiles));
    _aliases = _collectAliases();
  }

  /// Retry phrases before a target name (normalized).
  static const retryPhrases = [
    'nochmal mit',
    'noch mal mit',
    'noch einmal mit',
    'nochmals mit',
    'versuch es mit',
    'encore avec',
    'encore une fois avec',
    'reessaie avec',
    'refais avec',
    'again with',
    'try again with',
    'retry with',
    'once more with',
  ];

  /// The rules.
  final RuleSet rules;

  /// Known profiles by id.
  final Map<String, RoutingProfile> profiles;

  /// Time source for `timeWindow`.
  final Clock clock;

  /// Connectivity for `network`.
  final NetworkStatus network;

  /// Tool categories for `needsTool`.
  final ToolCategoryMatcher matcher;

  /// Warnings about [rules] (skipped rules, weak private targets …).
  late final List<RuleSetIssue> issues;

  late final List<(String, RouteTarget)> _aliases;

  /// The routing context for [input] right now.
  RoutingContext contextFor(UserInput input) => RoutingContext(
    input: input,
    now: clock.now(),
    network: network.current,
    matcher: matcher,
  );

  @override
  Resolution resolve(UserInput input) {
    final ctx = contextFor(input);
    final decision = decideRoute(
      rules,
      ctx,
      profiles: profiles,
      needProvider: true,
    );
    final target = _build(decision.target)!;
    final requested = _requested(ctx.text);
    return Resolution(
      target: target,
      reason: decision.reason,
      privacyFloor: decision.private ? target.privacy : null,
      effectiveText: decision.effectiveText,
      requestedTarget: requested == null ? null : _build(requested),
      routeProfileId: target.profileId,
    );
  }

  @override
  Resolution? escalate(Resolution current, EscalationReason reason) {
    final floor = current.privacyFloor;
    final route = current.routeProfileId ?? current.profileId;
    final requested = current.requestedTarget;
    if (reason == EscalationReason.userRequested &&
        requested != null &&
        !_same(requested, current.target)) {
      return Resolution(
        target: requested,
        reason: 'Nutzerwunsch: ${profiles[requested.profileId]?.name}',
        privacyFloor: floor,
        routeProfileId: route,
      );
    }
    final chain = [for (final t in rules.chainOf(route)) ?_build(t)];
    final index = chain.indexWhere((t) => _same(t, current.target));
    final remaining = chain
        .skip(index + 1)
        .where((t) => !_same(t, current.target))
        .toList();
    if (remaining.isEmpty) return null;
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
      routeProfileId: route,
    );
  }

  static bool _same(ProviderTarget a, ProviderTarget b) =>
      a.profileId == b.profileId && a.modelId == b.modelId;

  ProviderTarget? _build(RouteTarget t) {
    final p = profiles[t.profileId];
    if (profileProblem(p, needProvider: true) != null) return null;
    return ProviderTarget(
      profileId: t.profileId,
      modelId: t.modelId,
      provider: p!.provider!,
      privacy: p.privacy,
    );
  }

  /// Names for „nochmal mit …“: rules first (they carry a specific
  /// model), then profiles.
  List<(String, RouteTarget)> _collectAliases() {
    final out = <(String, RouteTarget)>[];
    void add(String name, RouteTarget t) {
      final n = RoutingText.normalize(name);
      if (n.isNotEmpty && _build(t) != null) out.add((n, t));
    }

    for (final rule in rules.rules) {
      if (!rule.enabled || problemOf(rule) != null) continue;
      for (final a in [...rule.aliases, ...rule.condition.triggerWords]) {
        add(a, rule.target);
      }
    }
    for (final p in profiles.values) {
      final t = RouteTarget(profileId: p.id, modelId: p.defaultModel);
      for (final a in [p.name, ...p.aliases]) {
        add(a, t);
      }
    }
    return out;
  }

  /// The target named after a retry phrase, or `null`. The longest
  /// matching name wins; on a tie the earlier source.
  RouteTarget? _requested(RoutingText text) {
    for (final phrase in retryPhrases) {
      final span = text.findPhrase(phrase);
      if (span == null) continue;
      final rest = text.normalized.substring(span.end).trim();
      (String, RouteTarget)? best;
      for (final alias in _aliases) {
        final a = alias.$1;
        final hit = rest == a || rest.startsWith('$a ');
        if (hit && (best == null || a.length > best.$1.length)) best = alias;
      }
      if (best != null) return best.$2;
    }
    return null;
  }
}
