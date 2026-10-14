// Agent providers: risk policy, undo, audit, session, provider configuration,
// adapter factory, agent factory and costs. Imported via `providers.dart`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../agent/agent_controller.dart';
import 'agent_factory.dart';
import 'attestation_log_writer.dart';
import 'audit_recorder.dart';
import 'core_providers.dart';
import 'costs.dart';
import 'integration_providers.dart';
import 'preference_models.dart';
import 'preferences.dart';
import 'provider_config.dart';
import 'routing.dart';
import 'sensitivity.dart';
import 'session_manager.dart';
import 'voice_providers.dart' show voiceSettingsProvider;

/// Risk policy with the user's per-tool confirmations (only stricter).
final riskPolicyProvider = Provider<RiskPolicy>((ref) {
  final policy = RiskPolicy();
  var confirmed = <String>{};
  void apply(ToolPrefs prefs) {
    for (final name in confirmed.difference(prefs.alwaysConfirm)) {
      policy.clearOverride(name);
    }
    for (final name in prefs.alwaysConfirm) {
      policy.setOverride(name, PolicyAction.confirm);
    }
    confirmed = prefs.alwaysConfirm;
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

/// Current conversation session; ending one forgets unlocked tools and
/// cached calendar data.
final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    conversations: ref.watch(storageProvider).conversations,
    clock: ref.watch(clockProvider),
    onSessionEnd: (id) {
      // „Unterhaltung privat“ ends with its session.
      ref.read(agentControllerProvider.notifier).sessionEnded(id);
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
final providerConfigProvider = FutureProvider<ProviderConfig?>((ref) {
  if (ref.watch(demoModeProvider)) {
    return ProviderConfig.demo(ref.watch(clockProvider));
  }
  return ref.watch(storedProviderConfigProvider.future);
});

/// The configuration from the stored profiles and routing rules.
/// Invalidate after profiles or rules changed (WP09, WP26).
final storedProviderConfigProvider = FutureProvider<ProviderConfig?>(
  (ref) => loadProviderConfig(
    storage: ref.watch(storageProvider),
    secrets: ref.watch(secretStoreProvider),
    catalog: ref.watch(modelCatalogProvider),
    create: ref.watch(llmProviderFactoryProvider),
    clock: ref.watch(clockProvider),
    network: ref.watch(networkStatusProvider),
  ),
);

/// Builds the adapter for a profile (fake in tests).
typedef LlmProviderFactory = LlmProvider Function(
  ProviderProfile profile,
  SecretReader secrets,
);

/// Adapter factory used by the provider setup and the configuration.
final llmProviderFactoryProvider = Provider<LlmProviderFactory>((ref) {
  final catalog = ref.watch(modelCatalogProvider);
  return (profile, secrets) =>
      ProviderFactory.create(profile, secrets, catalog: catalog);
});

/// Builds the agent for each request.
final agentFactoryProvider = Provider<AgentRunFactory>((ref) {
  final storage = ref.watch(storageProvider);
  final assistant = ref.watch(assistantPrefsProvider);
  final twoVersions = ref.watch(
    voiceSettingsProvider.select((s) => s.value?.twoVersions ?? false),
  );
  return AgentFactory(
    config: AgentConfig(
      userName: assistant.userName,
      personaAddon: assistant.persona,
      spokenVersions: twoVersions,
    ),
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
