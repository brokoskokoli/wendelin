import 'dart:async';

// Agent providers: risk policy, undo, audit, session, provider configuration,
// adapter factory, agent factory and costs. Imported via `providers.dart`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart' show SessionOrigin;
import 'package:wendelin_tools/wendelin_tools.dart';

import '../agent/agent_controller.dart';
import '../voice/dev_agent_log.dart';
import 'agent_factory.dart';
import 'attest_log.dart';
import 'attestation_hub.dart' show AttestationHub;
import 'attestation_log_writer.dart';
import 'attestation_providers.dart';
import 'audit_recorder.dart';
import 'core_providers.dart';
import 'costs.dart';
import 'developer_mode.dart';
import 'home_assistant.dart' show haIntegrationOf;
import 'integration_providers.dart';
import 'preference_models.dart';
import 'preferences.dart';
import 'provider_config.dart';
import 'routing.dart';
import 'sensitivity.dart';
import 'session_lock_store.dart';
import 'session_manager.dart';
import 'voice_providers.dart' show voiceSettingsProvider;

/// Tools whose level is not chosen per tool: the Home Assistant call tools
/// take the level of the device (WP154), a tool level would bypass it.
bool toolLevelPerDevice(String tool) =>
    tool == 'ha__call' || tool == 'ha__call_secure';

/// Risk policy with the user's per-tool security levels (WP154, ADR 0022):
/// the level replaces the old "always confirm" and may also loosen a tool.
final riskPolicyProvider = Provider<RiskPolicy>((ref) {
  final policy = RiskPolicy(
    lockStore: SettingsSessionLockStore(ref.watch(storageProvider).settings),
  );
  var known = <String>{};
  void apply(ToolPrefs prefs) {
    // The call tools of Home Assistant only keep the legacy "always
    // confirm" (D); a chosen level would bypass the device's own level.
    String? raw(String n) => toolLevelPerDevice(n)
        ? (prefs.alwaysConfirm.contains(n) ? 'd' : null)
        : prefs.levelOf(n);
    final names = {
      for (final n in {...prefs.levels.keys, ...prefs.alwaysConfirm})
        if (raw(n) != null) n,
    };
    for (final name in known.difference(names)) {
      policy.clearLevel(name);
    }
    for (final name in names) {
      // Fail-closed: a stored level that is not a..d means D.
      policy.setLevel(
        name,
        SecurityLevel.effective(raw(name), SecurityLevel.d),
      );
    }
    known = names;
  }

  apply(ref.read(toolPrefsProvider));
  ref.listen(toolPrefsProvider, (_, next) => apply(next));
  return policy;
});

/// Undo offers of `write` tools (10 s).
final undoManagerProvider = Provider<UndoManager>((ref) {
  final manager = UndoManager(clock: ref.watch(clockProvider));
  ref.onDispose(manager.dispose);
  return manager;
});

/// Verification log (Prüfprotokoll) writer; the log sink of TEE providers.
final attestationLogWriterProvider = Provider<AttestationLogWriter>(
  (ref) => AttestationLogWriter(ref.watch(storageProvider).attestations),
);

/// Audit log writer.
final auditRecorderProvider = Provider<AuditRecorder>(
  (ref) => AuditRecorder(
    ref.watch(storageProvider).audit,
    clock: ref.watch(clockProvider),
    attestation: ref.watch(attestationLogWriterProvider),
  ),
);

/// Which engine this is; the overlay overrides it with
/// [SessionOrigin.overlay] so it keeps its own sessions (WP67).
final sessionOriginProvider = Provider<SessionOrigin>(
  (ref) => SessionOrigin.app,
);

/// Current conversation session; ending one forgets unlocked tools and
/// cached calendar data.
final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    conversations: ref.watch(storageProvider).conversations,
    clock: ref.watch(clockProvider),
    origin: ref.watch(sessionOriginProvider),
    onSessionEnd: (id) {
      // „Unterhaltung privat“ ends with its session.
      ref.read(agentControllerProvider.notifier).sessionEnded(id);
      // A red receipt locked its conversation; it ends with it (WP157).
      ref.read(riskPolicyProvider).endSession(id);
      // Read lazily: the registry may have been rebuilt meanwhile.
      ref.read(toolRegistryProvider).endSession(id);
      final integrations = ref.read(integrationsProvider);
      for (final spec in ref.read(integrationSpecsProvider)) {
        final integration = integrations[spec.id];
        if (integration != null) {
          spec.onSessionEnd?.call(unwrapIntegration(integration));
        }
      }
    },
  );
  ref.onDispose(manager.dispose);
  return manager;
});

/// Where requests go; `null` = no provider set up yet. In demo mode the
/// scripted demo provider, otherwise [storedProviderConfigProvider].
final FutureProvider<ProviderConfig?> providerConfigProvider =
    FutureProvider<ProviderConfig?>((ref) {
      if (ref.watch(demoModeProvider)) {
        return ProviderConfig.demo(ref.watch(clockProvider));
      }
      return ref.watch(storedProviderConfigProvider.future);
    });

/// The configuration from the stored profiles and routing rules.
/// Invalidate after profiles or rules changed (WP09, WP26).
final FutureProvider<ProviderConfig?> storedProviderConfigProvider =
    FutureProvider<ProviderConfig?>((ref) async {
      final profiles = await ref.watch(storageProvider).providerProfiles.list();
      if (anyNeedsAttestation(profiles)) {
        await awaitCheckModule(ref.read(attestationCryptoProvider.future));
      }
      return loadProviderConfig(
        storage: ref.watch(storageProvider),
        secrets: ref.watch(secretStoreProvider),
        catalog: ref.watch(modelCatalogProvider),
        create: hubRegistering(
          ref.read(attestationHubProvider),
          ref.watch(llmProviderFactoryProvider),
        ),
        clock: ref.watch(clockProvider),
        network: ref.watch(networkStatusProvider),
      );
    });

/// Wraps [create] so the live providers (and only those) are registered in
/// the hub. The setup probe instances are not: a probe provider must not
/// replace the live one (mode, locks, reports; WP82).
LlmProviderFactory hubRegistering(
  AttestationHub hub,
  LlmProviderFactory create,
) => (profile, secrets) {
  final provider = create(profile, secrets);
  if (provider is AttestedProvider && hub.provider(profile.id) != provider) {
    final seen = _registeredIds[hub] ??= <String>{};
    hub.register(
      profile.id,
      provider,
      // Registered by this wiring before: the profile changed (WP81).
      reason: seen.contains(profile.id)
          ? 'Profil geändert'
          : hub.provider(profile.id) != null
          ? 'Sitzung übernommen'
          : 'erster Aufbau',
    );
    seen.add(profile.id);
  }
  return provider;
};

final Expando<Set<String>> _registeredIds = Expando<Set<String>>();

/// Builds the adapter for a profile (fake in tests).
typedef LlmProviderFactory = LlmProvider Function(
  ProviderProfile profile,
  SecretReader secrets,
);

/// Adapter factory used by the provider setup and the configuration.
final Provider<LlmProviderFactory> llmProviderFactoryProvider =
    Provider<LlmProviderFactory>((ref) {
      final catalog = ref.watch(modelCatalogProvider);
      final transport = ref.watch(attestationTransportProvider);
      // Live TEE providers by profile (WP81): a config reload (any profile
      // or rule edit rebuilds all profiles) keeps the instance of a profile
      // that did not change, with its session, lock and connection.
      final live = <String, ({ProviderProfile profile, AttestedProvider p})>{};
      return (profile, secrets) {
        final kept = live[profile.id];
        if (kept != null && kept.profile == profile) return kept.p;
        final wiring = needsAttestation(profile)
            ? attestationWiringOf(ref)
            : null;
        if (needsAttestation(profile) && wiring == null) {
          throw ArgumentError.value(
            profile.id,
            'profile',
            'Das Prüfmodul für TEE-Anbieter ist nicht verfügbar',
          );
        }
        final provider = ProviderFactory.create(
          profile,
          secrets,
          catalog: catalog,
          attestation: wiring,
          client: transport?.client,
          settings: attestSettings(transport?.settings),
        );
        if (provider is AttestedProvider) {
          live[profile.id] = (profile: profile, p: provider);
        }
        return provider;
      };
    });

/// Builds the agent for each request.
final agentFactoryProvider = Provider<AgentRunFactory>((ref) {
  final storage = ref.watch(storageProvider);
  final assistant = ref.watch(assistantPrefsProvider);
  final spokenVersion = ref.watch(
    voiceSettingsProvider.select(
      (s) => s.value?.spokenVersion ?? SpokenVersion.off,
    ),
  );
  return AgentFactory(
    config: AgentConfig(
      userName: assistant.userName,
      personaAddon: assistant.persona,
      spokenVersion: spokenVersion,
    ),
    observe: (run) => ref
        .read(devAgentTraceProvider)
        .observe(() => unawaited(refreshDevLogFlag(ref)), run),
    fastPath: ref.watch(haFastPathProvider)
        ? haIntegrationOf(ref.watch(integrationsProvider))?.fastPath
        : null,
    registry: ref.watch(toolRegistryProvider),
    storage: storage,
    policy: ref.watch(riskPolicyProvider),
    audit: ref.watch(auditRecorderProvider),
    clock: ref.watch(clockProvider),
    device: ref.watch(deviceInfoProvider),
    costEstimator: CatalogCostEstimator(
      CostCalculator(ref.watch(modelCatalogProvider)),
    ),
    budgetGuard: RepositoryBudgetGuard(
      profiles: storage.providerProfiles,
      usage: storage.usage,
    ),
  );
});

/// Cost of today over all providers (micro-USD); refreshed after usage.
final todayCostProvider = FutureProvider<int>(
  (ref) => todayCostMicros(
    ref.watch(storageProvider).usage,
    ref.watch(clockProvider).now(),
  ),
);

/// Whether reasoning text is shown in the conversation.
final showThinkingProvider = Provider<bool>(
  (ref) => ref.watch(startupProvider).showThinking,
);
