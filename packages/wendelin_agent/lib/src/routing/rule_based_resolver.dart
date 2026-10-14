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
/// - `escalate`: only for „nochmal mit Name“ (de/fr/en) with a profile name,
///   a profile alias, a rule alias or a rule's prefix/keyword word: goes
///   directly to that target; the floor stays. There is no automatic
///   switch after errors (K28).
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
    final requested = _requested(ctx.text);
    final routed = _build(decision.target)!;
    final floor = _floorOf(decision.privateMatches);
    if (floor == null || routed.privacy.isAtLeast(floor)) {
      return Resolution(
        target: routed,
        reason: decision.reason,
        privacyFloor: floor,
        effectiveText: decision.effectiveText,
        requestedTarget: requested == null ? null : _build(requested),
      );
    }
    // Private, but the winning rule's target is too weak (or the private
    // rule's own target is unavailable): privacy wins over rule order.
    final (target, reason) =
        _compliant(decision.privateMatches, floor) ?? (routed, decision.reason);
    return Resolution(
      target: target,
      reason: reason,
      privacyFloor: floor,
      requestedTarget: requested == null ? null : _build(requested),
    );
  }

  /// The floor of the matched private rules: the highest level of their
  /// targets; an unavailable target counts as [PrivacyLevel.tee].
  PrivacyLevel? _floorOf(List<RoutingRule> privateRules) {
    PrivacyLevel? floor;
    for (final rule in privateRules) {
      final level = _build(rule.target)?.privacy ?? PrivacyLevel.tee;
      if (floor == null || level.isAtLeast(floor)) floor = level;
    }
    return floor;
  }

  /// The first available target with at least [floor]: the private rules'
  /// targets, then the default target.
  (ProviderTarget, String)? _compliant(
    List<RoutingRule> privateRules,
    PrivacyLevel floor,
  ) {
    final candidates = [
      for (final rule in privateRules) (rule.target, rule.name),
      (rules.defaultTarget, RuleSet.defaultReason),
    ];
    for (final (t, reason) in candidates) {
      final built = _build(t);
      if (built != null && built.privacy.isAtLeast(floor)) {
        return (built, reason);
      }
    }
    return null;
  }

  @override
  Resolution? escalate(Resolution current, EscalationReason reason) {
    final floor = current.privacyFloor;
    final requested = current.requestedTarget;
    if (reason == EscalationReason.userRequested && requested != null) {
      // „nochmal mit <aktuelles Ziel>“ retries on the same target.
      final again = _same(requested, current.target);
      return Resolution(
        target: again ? current.target : requested,
        reason: again
            ? 'Nutzerwunsch: erneut'
            : 'Nutzerwunsch: ${profiles[requested.profileId]?.name}',
        privacyFloor: floor,
      );
    }
    return null;
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
      name: p.name,
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

  /// Words that may stand before a retry phrase („Kannst du das nochmal
  /// mit Claude machen?“), normalized.
  static const retryFillers = {
    'bitte', 'kannst', 'du', 'das', 'es', 'mach', 'machs', 'frag', 'ok', //
    'okay', 'nein', 'also', 'und', 'jetzt', 'versuch', 'probier', 'dann',
    'please', 'can', 'you', 'do', 'it', 'that', 'try', 'now', 'no', 'and',
    'so', 'then', 'ask',
    'peux', 'tu', 'le', 'fais', 'essaie', 's', 'il', 'te', 'plait', 'non',
    'et', 'alors', 'maintenant', 'demande',
  };

  /// Most filler words before and extra words after the name.
  static const maxFillers = 4, maxTrailingWords = 2;

  /// The target named after a retry phrase, or `null`. The phrase must
  /// start the request (after at most [maxFillers] [retryFillers]) and the
  /// name may be followed by at most [maxTrailingWords] words, so dictated
  /// sentences („Schreib Anna: ich gehe nochmal mit Claude ins Kino“) do
  /// not count. The longest matching name wins; on a tie the earlier source
  /// (rules before profiles).
  RouteTarget? _requested(RoutingText text) {
    final words = text.normalized.isEmpty
        ? const <String>[]
        : text.normalized.split(' ');
    var start = 0;
    while (start < words.length &&
        start < maxFillers &&
        retryFillers.contains(words[start])) {
      start++;
    }
    for (var at = 0; at <= start; at++) {
      for (final phrase in retryPhrases) {
        final p = phrase.split(' ');
        if (!_wordsAt(words, at, p)) continue;
        final rest = words.sublist(at + p.length);
        (String, RouteTarget)? best;
        for (final alias in _aliases) {
          final a = alias.$1.split(' ');
          if (!_wordsAt(rest, 0, a)) continue;
          if (rest.length - a.length > maxTrailingWords) continue;
          if (best == null || alias.$1.length > best.$1.length) best = alias;
        }
        if (best != null) return best.$2;
      }
    }
    return null;
  }

  static bool _wordsAt(List<String> words, int at, List<String> phrase) {
    if (at + phrase.length > words.length) return false;
    for (var i = 0; i < phrase.length; i++) {
      if (words[at + i] != phrase[i]) return false;
    }
    return true;
  }
}
