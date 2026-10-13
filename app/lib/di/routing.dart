import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/fakes.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/channel_network_status.dart';
import 'app_settings.dart';
import 'profiles.dart';
import 'providers.dart';

// Routing rules of the app (WP26, ADR 0009): stored as JSON in the
// settings, migrated once from the M2 escalation chain, edited on the
// routing page and turned into a `RuleBasedProviderResolver` by
// `loadProviderConfig`.

/// Settings keys of the routing.
abstract final class RoutingSettings {
  /// The rule set (`RuleSetJson`, schema version 1). Absent until the first
  /// load with a default profile migrates the M2 settings.
  static final rules = SettingKey<RuleSet>(
    'routing.rules',
    encode: (r) => RuleSetJson().encode(r),
    decode: (json) => RuleSetJson().decode(json),
  );

  /// One-time hint after the migration switched the rule „Privat“ on:
  /// the name of its target profile. Removed when the user dismisses it.
  static final privateRuleNotice = SettingKey.string(
    'routing.privateRuleNotice',
  );
}

/// Id of the preset rule „Privat“.
const privateRuleId = 'privat';

/// The preset rule „Privat“ (replaces the M2 `ProviderConfig.isPrivate`
/// callback): the `privacy` condition with its default words, aimed at the
/// default profile if it is TEE or local, else at the first such profile.
/// Without one the rule is created switched off; the editor then shows the
/// warning `privacyTargetTooWeak` as hint.
RoutingRule privatePresetRule(
  List<ProviderProfile> profiles,
  ProviderProfile defaultProfile,
) {
  bool strong(ProviderProfile p) => p.privacy.isAtLeast(PrivacyLevel.tee);
  final target = strong(defaultProfile)
      ? defaultProfile
      : profiles.where(strong).firstOrNull;
  final to = target ?? defaultProfile;
  return RoutingRule(
    id: privateRuleId,
    name: 'Privat',
    condition: PrivacyCondition(),
    target: RouteTarget(profileId: to.id, modelId: to.defaultModel),
    enabled: target != null,
  );
}

/// Migration of the M2 settings (ADR 0009 §5): the global escalation chain
/// becomes the chain of the default profile, plus the preset rule
/// „Privat“. Unknown profile ids in [legacyChain] are dropped.
RuleSet migrateRuleSet({
  required List<ProviderProfile> profiles,
  required ProviderProfile defaultProfile,
  required List<String> legacyChain,
}) {
  final byId = {for (final p in profiles) p.id: p};
  return RuleSet.fromGlobalChain(
    defaultTarget: RouteTarget(
      profileId: defaultProfile.id,
      modelId: defaultProfile.defaultModel,
    ),
    globalChain: [
      for (final id in legacyChain)
        if (byId[id] case final p?)
          RouteTarget(profileId: p.id, modelId: p.defaultModel),
    ],
    rules: [privatePresetRule(profiles, defaultProfile)],
  );
}

/// The stored rule set, `null` without a default profile.
///
/// The first call with a default profile migrates the M2 settings
/// ([migrateRuleSet]) and stores the result. The default profile of the
/// profile list stays the source of truth for the default target's
/// profile: if it changed (set or deleted in „Provider“), the rule set
/// follows with that profile's default model.
///
/// Throws a [RuleSetFormatException] if the stored JSON cannot be read.
Future<RuleSet?> loadRuleSet(WendelinStorage storage) async {
  final defaultProfile = await storage.providerProfiles.defaultProfile();
  if (defaultProfile == null) return null;
  final settings = storage.settings;
  var rules = await settings.get(RoutingSettings.rules);
  if (rules == null) {
    rules = migrateRuleSet(
      profiles: await storage.providerProfiles.list(),
      defaultProfile: defaultProfile,
      legacyChain: await settings.get(AppSettings.escalationChain) ?? const [],
    );
    await settings.set(RoutingSettings.rules, rules);
    final privat = rules.rules.where((r) => r.id == privateRuleId).first;
    if (privat.enabled) {
      final target = await storage.providerProfiles.get(
        privat.target.profileId,
      );
      await settings.set(
        RoutingSettings.privateRuleNotice,
        target?.name ?? privat.target.profileId,
      );
    }
  } else if (rules.defaultTarget.profileId != defaultProfile.id) {
    rules = rules.copyWith(
      defaultTarget: RouteTarget(
        profileId: defaultProfile.id,
        modelId: defaultProfile.defaultModel,
      ),
    );
    await settings.set(RoutingSettings.rules, rules);
  }
  return rules;
}

/// The default model of profile [profileId] changed from [from] to [to]
/// (provider settings): every routing target that used the old default
/// model of that profile (default target, rules, chain links) follows.
/// Targets with another model were chosen on purpose and stay.
Future<void> followDefaultModel(
  WendelinStorage storage, {
  required String profileId,
  required String from,
  required String to,
}) async {
  if (from == to) return;
  final rules = await storage.settings.get(RoutingSettings.rules);
  if (rules == null) return;
  final old = RouteTarget(profileId: profileId, modelId: from);
  final now = RouteTarget(profileId: profileId, modelId: to);
  RouteTarget follow(RouteTarget t) => t == old ? now : t;
  final updated = rules.copyWith(
    defaultTarget: follow(rules.defaultTarget),
    rules: [for (final r in rules.rules) r.copyWith(target: follow(r.target))],
    chains: {
      for (final MapEntry(:key, :value) in rules.chains.entries)
        key: value.map(follow).toList(),
    },
  );
  if (updated != rules) {
    await storage.settings.set(RoutingSettings.rules, updated);
  }
}

/// The pending hint about the new rule „Privat“ (target profile name), or
/// `null`. Re-read after the configuration (and with it the migration)
/// loaded.
final privateRuleNoticeProvider = FutureProvider<String?>((ref) async {
  await ref.watch(storedProviderConfigProvider.future).catchError((_) => null);
  return ref
      .watch(storageProvider)
      .settings
      .get(RoutingSettings.privateRuleNotice);
});

/// Dismisses the hint about the rule „Privat“.
Future<void> dismissPrivateRuleNotice(WidgetRef ref) async {
  await ref
      .read(storageProvider)
      .settings
      .remove(RoutingSettings.privateRuleNotice);
  ref.invalidate(privateRuleNoticeProvider);
}

/// Text of the hint about the rule „Privat“ for [target].
String privateRuleNoticeText(String target) =>
    'Neu: Regel „Privat“ – Anfragen mit „privat“, „vertraulich“ … gehen an '
    '$target und bleiben bei Eskalationen auf dessen Datenschutzstufe.';

/// [profile] as the router sees it (no adapter: for the editor).
RoutingProfile routingProfileOf(
  ProviderProfile profile, {
  LlmProvider? provider,
}) => RoutingProfile(
  id: profile.id,
  name: profile.name,
  privacy: profile.privacy,
  defaultModel: profile.defaultModel,
  provider: provider,
);

/// Connectivity for the `network` condition: the platform channel on the
/// device, always online in the demo mode.
final networkStatusProvider = Provider<NetworkStatus>((ref) {
  if (ref.watch(demoModeProvider)) return FixedNetworkStatus();
  final status = ChannelNetworkStatus()..start();
  ref.onDispose(status.dispose);
  return status;
});

/// What the routing page edits.
@immutable
final class RoutingState {
  /// Creates the state.
  RoutingState({required this.rules, required List<ProviderProfile> profiles})
    : profiles = List.unmodifiable(profiles);

  /// The rules; `null` = no default profile yet.
  final RuleSet? rules;

  /// All provider profiles.
  final List<ProviderProfile> profiles;

  /// [profiles] for `explain` and `validateRuleSet`.
  late final Map<String, RoutingProfile> routingProfiles = {
    for (final p in profiles) p.id: routingProfileOf(p),
  };

  /// Warnings about [rules].
  late final List<RuleSetIssue> issues = rules == null
      ? const []
      : validateRuleSet(rules!, routingProfiles);

  /// The profile [id], or `null`.
  ProviderProfile? profile(String id) =>
      profiles.where((p) => p.id == id).firstOrNull;

  /// Display name of profile [id] (the id if it is gone).
  String nameOf(String id) => profile(id)?.name ?? id;
}

/// Rules for the routing page; saving refreshes the agent's configuration.
final routingProvider = AsyncNotifierProvider<RoutingNotifier, RoutingState>(
  RoutingNotifier.new,
);

/// Loads and stores the routing rules.
final class RoutingNotifier extends AsyncNotifier<RoutingState> {
  @override
  Future<RoutingState> build() async {
    final storage = ref.watch(storageProvider);
    final rules = await loadRuleSet(storage);
    return RoutingState(
      rules: rules,
      profiles: await storage.providerProfiles.list(),
    );
  }

  /// Stores [rules]. A new default target profile also becomes the default
  /// profile of the provider list.
  Future<void> save(RuleSet rules) async {
    // Show the change right away (no flicker while dragging).
    if (state.value case final current?) {
      state = AsyncData(RoutingState(rules: rules, profiles: current.profiles));
    }
    final storage = ref.read(storageProvider);
    final current = await storage.providerProfiles.defaultProfile();
    if (current?.id != rules.defaultTarget.profileId) {
      await storage.providerProfiles.setDefault(rules.defaultTarget.profileId);
    }
    await storage.settings.set(RoutingSettings.rules, rules);
    _refresh();
    await future;
  }

  /// Drops the stored rules; the next load migrates afresh (repair of an
  /// unreadable rule set).
  Future<void> reset() async {
    await ref.read(storageProvider).settings.remove(RoutingSettings.rules);
    _refresh();
    await future;
  }

  void _refresh() {
    ref
      ..invalidate(storedProviderConfigProvider)
      ..invalidate(profilesProvider)
      ..invalidateSelf();
  }
}
