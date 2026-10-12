import 'package:flutter/foundation.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';
import 'demo_provider.dart';

/// The providers a request can go to: the default target and the
/// escalation chain, plus display names per profile.
@immutable
final class ProviderConfig {
  /// Creates a configuration.
  ProviderConfig({
    required this.primary,
    List<ProviderTarget> chain = const [],
    Map<String, String> names = const {},
  }) : chain = List.unmodifiable(chain),
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

  /// Where every request goes first.
  final ProviderTarget primary;

  /// Escalation chain after [primary], weakest first.
  final List<ProviderTarget> chain;

  /// Display name per profile id.
  final Map<String, String> names;

  /// Display name of [profileId] (the id if unknown).
  String nameOf(String profileId) => names[profileId] ?? profileId;

  /// The lowest privacy level among all targets. The tool catalog is built
  /// for it, so an escalation never sends sensitive tools to a provider
  /// that may not see them.
  PrivacyLevel get lowestPrivacy => [
    primary,
    ...chain,
  ].map((t) => t.privacy).reduce((a, b) => a.isAtLeast(b) ? b : a);

  /// The resolver for the agent.
  ProviderResolver resolver() => DefaultProviderResolver(primary, chain);
}

/// Loads the [ProviderConfig] from the stored profiles: the default profile
/// and the escalation chain from the settings. Returns `null` if no default
/// profile is set (the main screen then offers „Provider einrichten“).
///
/// Chain entries that are unknown or cannot be built are skipped; a broken
/// default profile throws.
Future<ProviderConfig?> loadProviderConfig({
  required WendelinStorage storage,
  required SecretStore secrets,
  required ModelCatalog catalog,
}) async {
  final profile = await storage.providerProfiles.defaultProfile();
  if (profile == null) return null;
  ProviderTarget target(ProviderProfile p) => ProviderTarget(
    profileId: p.id,
    modelId: p.defaultModel,
    provider: ProviderFactory.create(p, secrets.read, catalog: catalog),
    privacy: p.privacy,
  );
  final names = {profile.id: profile.name};
  final chain = <ProviderTarget>[];
  final ids = await storage.settings.get(AppSettings.escalationChain) ?? [];
  for (final id in ids) {
    if (id == profile.id) continue;
    final p = await storage.providerProfiles.get(id);
    if (p == null) continue;
    try {
      chain.add(target(p));
      names[p.id] = p.name;
    } on ArgumentError {
      // Not buildable (e.g. missing base URL): not part of the chain.
    }
  }
  return ProviderConfig(primary: target(profile), chain: chain, names: names);
}
