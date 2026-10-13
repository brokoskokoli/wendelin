import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';
import 'providers.dart';

/// Stored provider profiles, the default and the escalation chain.
@immutable
final class ProfilesState {
  /// Creates the state.
  ProfilesState({
    required List<ProviderProfile> profiles,
    required this.defaultId,
    required List<String> chain,
  }) : profiles = List.unmodifiable(profiles),
       chain = List.unmodifiable(chain);

  /// All profiles in insertion order.
  final List<ProviderProfile> profiles;

  /// Id of the default profile.
  final String? defaultId;

  /// Escalation chain after the default, weakest first.
  final List<String> chain;

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
    final profiles = await storage.providerProfiles.list();
    final ids = {for (final p in profiles) p.id};
    final chain = await storage.settings.get(AppSettings.escalationChain);
    return ProfilesState(
      profiles: profiles,
      defaultId: (await storage.providerProfiles.defaultProfile())?.id,
      chain: [
        for (final id in chain ?? const <String>[])
          if (ids.contains(id)) id,
      ],
    );
  }

  /// Stores [profile]; the first profile (or [makeDefault]) becomes the
  /// default.
  Future<void> save(ProviderProfile profile, {bool makeDefault = false}) =>
      _change((storage) async {
        await storage.providerProfiles.save(profile);
        final hasDefault = await storage.providerProfiles.defaultProfile();
        if (makeDefault || hasDefault == null) {
          await storage.providerProfiles.setDefault(profile.id);
        }
      });

  /// Deletes profile [id] with its secrets and removes it from the chain.
  /// If it was the default, the first remaining profile becomes the default.
  Future<void> delete(String id) => _change((storage) async {
    final profile = await storage.providerProfiles.get(id);
    if (profile == null) return;
    final secrets = ref.read(secretStoreProvider);
    for (final secretRef in profile.authMethod.secretRefs) {
      await secrets.delete(secretRef);
    }
    await storage.providerProfiles.delete(id);
    final chain = await storage.settings.get(AppSettings.escalationChain);
    await storage.settings.set(AppSettings.escalationChain, [
      for (final c in chain ?? const <String>[])
        if (c != id) c,
    ]);
    if (await storage.providerProfiles.defaultProfile() == null) {
      final rest = await storage.providerProfiles.list();
      if (rest.isNotEmpty) {
        await storage.providerProfiles.setDefault(rest.first.id);
      }
    }
  });

  /// Makes [id] the default profile (and removes it from the chain).
  Future<void> setDefault(String id) => _change((storage) async {
    await storage.providerProfiles.setDefault(id);
    final chain = await storage.settings.get(AppSettings.escalationChain);
    await storage.settings.set(AppSettings.escalationChain, [
      for (final c in chain ?? const <String>[])
        if (c != id) c,
    ]);
  });

  /// Stores the escalation chain [ids] (order = order of escalation).
  Future<void> setChain(List<String> ids) => _change(
    (storage) => storage.settings.set(AppSettings.escalationChain, ids),
  );

  Future<void> _change(
    Future<void> Function(WendelinStorage storage) body,
  ) async {
    await body(ref.read(storageProvider));
    ref
      ..invalidate(storedProviderConfigProvider)
      ..invalidateSelf();
    await future;
  }
}
