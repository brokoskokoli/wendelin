import 'package:flutter/foundation.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'demo_provider.dart';
import 'routing.dart';

/// The rules and profiles behind a [ProviderConfig] with routing rules
/// (M3, ADR 0009).
@immutable
final class RoutingSetup {
  /// Creates the setup; [profiles] are copied.
  RoutingSetup({
    required this.rules,
    required List<RoutingProfile> profiles,
    required this.clock,
    required this.network,
  }) : profiles = List.unmodifiable(profiles);

  /// The stored rules.
  final RuleSet rules;

  /// All profiles; those whose adapter cannot be built have none.
  final List<RoutingProfile> profiles;

  /// Time for `timeWindow`.
  final Clock clock;

  /// Connectivity for `network`.
  final NetworkStatus network;
}

/// The providers a request can go to: the default target and the further
/// targets (with routing rules every other available profile; they only get
/// a request by a rule or the user's „nochmal mit …“, never after an
/// error, K28), plus display names per profile.
@immutable
final class ProviderConfig {
  /// Creates a configuration. With [routing] requests are routed by rules
  /// (`RuleBasedProviderResolver`); without, everything goes to [primary]
  /// and nothing else (`DefaultProviderResolver`, demo mode and device
  /// tests); [others] only widens the tool catalog and memory checks.
  ProviderConfig({
    required this.primary,
    List<ProviderTarget> others = const [],
    Map<String, String> names = const {},
    this.isPrivate,
    this.routing,
  }) : others = List.unmodifiable(others),
       names = Map.unmodifiable(names);

  /// Demo mode: everything goes to the scripted [DemoLlmProvider].
  factory ProviderConfig.demo(Clock clock) => ProviderConfig(
    primary: ProviderTarget(
      profileId: DemoLlmProvider.profileId,
      modelId: DemoLlmProvider.modelId,
      provider: DemoLlmProvider(
        clock: clock,
        eventDelay: const Duration(milliseconds: 25),
      ),
      privacy: PrivacyLevel.local,
    ),
    names: const {DemoLlmProvider.profileId: 'Demo · Skript'},
  );

  /// The default target.
  final ProviderTarget primary;

  /// Further targets: with [routing] every other available profile (with
  /// its default model). Never used automatically (K28).
  final List<ProviderTarget> others;

  /// Display name per profile id.
  final Map<String, String> names;

  /// Without [routing]: marks a request as privately routed (its privacy
  /// level is then the floor); `null` = never.
  final bool Function(UserInput input)? isPrivate;

  /// Routing rules; `null` = default target only.
  final RoutingSetup? routing;

  /// Whether profile [profileId] encrypts tool definitions, calls and
  /// results end to end too (NEAR AI, WP75); `false` if unknown.
  bool toolsEncryptedFor(String profileId) => [primary, ...others].any(
    (t) =>
        t.profileId == profileId &&
        t.provider is AttestedProvider &&
        (t.provider as AttestedProvider).toolsEncrypted,
  );

  /// Display name of [profileId] (the id if unknown).
  String nameOf(String profileId) => names[profileId] ?? profileId;

  /// The target of profile [id] (the one answering right now), else the
  /// primary target.
  ProviderTarget targetFor(String? id) {
    for (final t in [primary, ...others]) {
      if (t.profileId == id) return t;
    }
    return primary;
  }

  /// The targets offered after a provider failure („Mit X nochmal?“,
  /// WP128): every configured target, those whose model is recommended
  /// (`modelRecommendations`) first. The agent drops the failed one and
  /// everything below its privacy level; nothing is ever used without the
  /// user's yes (K28).
  List<ProviderTarget> fallbackTargets() {
    bool recommended(ProviderTarget t) => modelRecommendations.values.any(
      (list) => list.any((r) => r.modelId == t.modelId),
    );
    final all = [primary, ...others];
    return [...all.where(recommended), ...all.where((t) => !recommended(t))];
  }

  /// The lowest privacy level among all targets a request can reach. The
  /// tool catalog is built for it, so neither a rule nor „nochmal mit …“
  /// sends sensitive tools to a provider that may not see them.
  PrivacyLevel get lowestPrivacy => [
    primary,
    ...others,
  ].map((t) => t.privacy).reduce((a, b) => a.isAtLeast(b) ? b : a);

  /// This configuration with the provider profile [profileId] as default
  /// target instead of the global one (the default of a recognized person,
  /// WP92b). Nothing else changes: the set of reachable targets, routing
  /// rules, privacy floor and taint stay as they are, and the stored default
  /// (`setDefault`) is not touched. Returns `this` if [profileId] is `null`,
  /// already the default or not a usable profile.
  ProviderConfig withDefaultProfile(String? profileId) {
    if (profileId == null || profileId == primary.profileId) return this;
    final chosen = others.where((t) => t.profileId == profileId).firstOrNull;
    if (chosen == null) return this;
    final r = routing;
    return ProviderConfig(
      primary: chosen,
      others: [
        primary,
        for (final t in others)
          if (t.profileId != profileId) t,
      ],
      names: names,
      isPrivate: isPrivate,
      routing: r == null
          ? null
          : RoutingSetup(
              rules: r.rules.copyWith(
                defaultTarget: RouteTarget(
                  profileId: chosen.profileId,
                  modelId: chosen.modelId,
                ),
              ),
              profiles: r.profiles,
              clock: r.clock,
              network: r.network,
            ),
    );
  }

  /// The resolver for the agent.
  ProviderResolver resolver() => switch (routing) {
    final r? => RuleBasedProviderResolver(
      rules: r.rules,
      profiles: r.profiles,
      clock: r.clock,
      network: r.network,
    ),
    null => DefaultProviderResolver(primary, isPrivate: isPrivate),
  };
}

/// Loads the [ProviderConfig] from the stored profiles and routing rules
/// ([loadRuleSet]).
/// Returns `null` if no default profile is set (the main screen then
/// offers „Provider einrichten“).
///
/// Profiles whose adapter cannot be built take no requests (rules to them
/// are skipped); a broken default profile throws.
Future<ProviderConfig?> loadProviderConfig({
  required WendelinStorage storage,
  required SecretStore secrets,
  required ModelCatalog catalog,
  LlmProvider Function(ProviderProfile profile, SecretReader secrets)? create,
  Clock clock = const SystemClock(),
  NetworkStatus? network,
}) async {
  final rules = await loadRuleSet(storage);
  if (rules == null) return null;
  LlmProvider build(ProviderProfile p) =>
      create?.call(p, secrets.read) ??
      ProviderFactory.create(p, secrets.read, catalog: catalog);
  final profiles = await storage.providerProfiles.list();
  final defaultId = rules.defaultTarget.profileId;
  final routing = <RoutingProfile>[];
  final names = <String, String>{};
  ProviderTarget? primary;
  final others = <ProviderTarget>[];
  for (final p in profiles) {
    names[p.id] = p.name;
    LlmProvider? provider;
    if (p.id == defaultId) {
      provider = build(p); // A broken default profile throws.
    } else {
      try {
        provider = build(p);
      } on ArgumentError {
        // Not buildable (e.g. missing base URL): takes no requests.
      }
    }
    routing.add(routingProfileOf(p, provider: provider));
    if (provider == null) continue;
    final target = ProviderTarget(
      profileId: p.id,
      modelId: p.id == defaultId ? rules.defaultTarget.modelId : p.defaultModel,
      provider: provider,
      privacy: effectivePrivacy(p),
      name: p.name,
    );
    if (p.id == defaultId) {
      primary = target;
    } else {
      others.add(target);
    }
  }
  if (primary == null) {
    throw StateError('Standardprofil $defaultId fehlt');
  }
  return ProviderConfig(
    primary: primary,
    others: others,
    names: names,
    routing: RoutingSetup(
      rules: rules,
      profiles: routing,
      clock: clock,
      network: network ?? FixedNetworkStatus(),
    ),
  );
}
