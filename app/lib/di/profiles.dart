import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'providers.dart';
import 'routing.dart';

/// Stored provider profiles and the default. Escalation chains belong to
/// the routing rules since M3 (`routing.dart`).
@immutable
final class ProfilesState {
  /// Creates the state.
  ProfilesState({
    required List<ProviderProfile> profiles,
    required this.defaultId,
  }) : profiles = List.unmodifiable(profiles);

  /// All profiles in insertion order.
  final List<ProviderProfile> profiles;

  /// Id of the default profile.
  final String? defaultId;

  /// The profile [id], or `null`.
  ProviderProfile? byId(String id) =>
      profiles.where((p) => p.id == id).firstOrNull;
}

/// Profiles for the settings; every change refreshes the provider
/// configuration of the agent.
final profilesProvider = AsyncNotifierProvider<ProfilesNotifier, ProfilesState>(
  ProfilesNotifier.new,
);

/// Manages provider profiles (no secrets except deleting them).
final class ProfilesNotifier extends AsyncNotifier<ProfilesState> {
  @override
  Future<ProfilesState> build() async {
    final storage = ref.watch(storageProvider);
    return ProfilesState(
      profiles: await storage.providerProfiles.list(),
      defaultId: (await storage.providerProfiles.defaultProfile())?.id,
    );
  }

  /// Stores [profile]; the first profile (or [makeDefault]) becomes the
  /// default. A changed default model also changes the routing targets
  /// that used the old one ([followDefaultModel]).
  Future<void> save(ProviderProfile profile, {bool makeDefault = false}) =>
      _change((storage) async {
        final before = await storage.providerProfiles.get(profile.id);
        await storage.providerProfiles.save(profile);
        if (before != null) {
          await followDefaultModel(
            storage,
            profileId: profile.id,
            from: before.defaultModel,
            to: profile.defaultModel,
          );
        }
        final hasDefault = await storage.providerProfiles.defaultProfile();
        if (makeDefault || hasDefault == null) {
          await storage.providerProfiles.setDefault(profile.id);
        }
      });

  /// Deletes profile [id] with its secrets. If it was the default, the
  /// first remaining profile becomes the default (the routing rules follow,
  /// see `loadRuleSet`); rules and chain links to it stay and are shown
  /// with a warning in the routing editor.
  Future<void> delete(String id) => _change((storage) async {
    final profile = await storage.providerProfiles.get(id);
    if (profile == null) return;
    final secrets = ref.read(secretStoreProvider);
    for (final secretRef in profile.authMethod.secretRefs) {
      await secrets.delete(secretRef);
    }
    await storage.providerProfiles.delete(id);
    if (await storage.providerProfiles.defaultProfile() == null) {
      final rest = await storage.providerProfiles.list();
      if (rest.isNotEmpty) {
        await storage.providerProfiles.setDefault(rest.first.id);
      }
    }
  });

  /// Makes [id] the default profile (also the default target of the
  /// routing rules).
  Future<void> setDefault(String id) =>
      _change((storage) => storage.providerProfiles.setDefault(id));

  Future<void> _change(
    Future<void> Function(WendelinStorage storage) body,
  ) async {
    await body(ref.read(storageProvider));
    ref
      ..invalidate(storedProviderConfigProvider)
      ..invalidate(routingProvider)
      ..invalidateSelf();
    await future;
  }
}
