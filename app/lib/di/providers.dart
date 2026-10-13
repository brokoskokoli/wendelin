import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../platform/platform_ports.dart';
import '../platform/secure_secret_store.dart';
import 'agent_factory.dart';
import 'app_requirements.dart';
import 'app_settings.dart';
import 'audit_recorder.dart';
import 'bring.dart';
import 'costs.dart';
import 'http_tools.dart';
import 'integration_activator.dart';
import 'integration_specs.dart';
import 'preference_models.dart';
import 'preferences.dart';
import 'provider_config.dart';
import 'routing.dart';
import 'sensitivity.dart';
import 'session_manager.dart';
import 'startup.dart';
import 'user_integrations.dart';
import 'web_search.dart';

// Riverpod wiring of the app. `main.dart` overrides [storageProvider],
// [startupProvider] and [deviceInfoProvider]; tests also override the ports
// and the provider configuration.

/// Time source.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Ids for profiles, lists and key references.
final idGeneratorProvider = Provider<IdGenerator>((ref) => UuidV4Generator());

/// Local database; overridden in `main.dart` (drift_flutter) and in tests
/// (in-memory).
final storageProvider = Provider<WendelinStorage>(
  (ref) => throw UnimplementedError('storageProvider muss gesetzt werden'),
);

/// Settings read once at start.
final startupProvider = Provider<StartupSettings>(
  (ref) => const StartupSettings(),
);

/// Locale and IANA time zone of the device; overridden in `main.dart`.
final deviceInfoProvider = Provider<DeviceInfo>(
  (ref) => const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
);

/// Secrets (Android Keystore).
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// Shared HTTP client for integrations.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Opens web addresses (download page of a missing app); throws a
/// `PortException` if nothing can open it.
final urlLauncherProvider = Provider<Future<void> Function(Uri url)>(
  (ref) => openExternalUrl,
);

/// Model prices.
final modelCatalogProvider = Provider<ModelCatalog>(
  (ref) => ModelCatalog.builtIn(),
);

/// Debug demo mode (scripted provider, in-memory ports). Always off in
/// release builds.
final demoModeProvider = NotifierProvider<DemoModeNotifier, bool>(
  DemoModeNotifier.new,
);

/// Switches the demo mode and stores the choice.
final class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() => kDebugMode && ref.watch(startupProvider).demoMode;

  /// Switches the demo mode on or off (no effect in release builds).
  Future<void> set({required bool enabled}) async {
    if (!kDebugMode) return;
    state = enabled;
    await ref.read(storageProvider).settings.set(AppSettings.demoMode, enabled);
  }
}

/// Ports of the real device.
final devicePortsProvider = Provider<PlatformPorts>(
  (ref) => PlatformPorts.device(
    ref.watch(storageProvider),
    listDefinitions: () => ref.read(listDefinitionsProvider),
    obsidian: () => ref.read(obsidianPrefsProvider),
    language: () => ref.read(languageProvider),
  ),
);

/// In-memory ports of the demo mode.
final demoPortsProvider = Provider<PlatformPorts>(
  (ref) => PlatformPorts.demo(),
);

/// Ports in use (demo or device).
final platformPortsProvider = Provider<PlatformPorts>(
  (ref) => ref.watch(demoModeProvider)
      ? ref.watch(demoPortsProvider)
      : ref.watch(devicePortsProvider),
);

/// Registered integrations (extension point, see [IntegrationSpec]).
final integrationSpecsProvider = Provider<List<IntegrationSpec>>(
  (ref) => builtInIntegrationSpecs,
);

/// Dependencies for building integrations.
final integrationDepsProvider = Provider<IntegrationDeps>((ref) {
  final demo = ref.watch(demoModeProvider);
  // The registry is built from these integrations, so it is reached
  // through a holder instead of a provider dependency.
  final holder = ref.watch(_currentRegistryProvider);
  void onRegistry(String id, void Function(ToolRegistry registry) action) {
    final registry = holder.registry;
    if (registry == null) return;
    if (registry.integrations.any((i) => i.id == id)) action(registry);
  }

  return IntegrationDeps(
    // Bring! talks to a real account: not in the demo mode.
    bringApi: demo ? null : ref.watch(bringApiProvider),
    bringSecrets: demo ? null : ref.watch(bringSecretsProvider),
    reportError: (id, message) =>
        onRegistry(id, (r) => r.reportError(id, message)),
    clearError: (id) => onRegistry(id, (r) => r.clearError(id)),
    ports: ref.watch(platformPortsProvider),
    device: ref.watch(deviceInfoProvider),
    httpClient: ref.watch(httpClientProvider),
    webSearch: switch (ref.watch(webSearchConfigProvider)) {
      null => null,
      final config => StoredKeyWebSearch(
        config,
        secrets: ref.watch(secretStoreProvider),
        client: ref.watch(httpClientProvider),
      ),
    },
  );
});

/// Last known answers of the app detection (hints for optional apps).
final installedAppsProvider = Provider<InstalledApps>(
  (ref) => InstalledApps(ref.watch(platformPortsProvider).apps),
);

/// The built integrations by id.
final integrationsProvider = Provider<Map<String, Integration>>((ref) {
  final deps = ref.watch(integrationDepsProvider);
  final marks = ref.watch(toolPrefsProvider.select((p) => p.sensitive));
  final apps = ref.watch(installedAppsProvider);
  return {
    for (final spec in ref.watch(integrationSpecsProvider))
      if (spec.isSupported?.call(deps) ?? true)
        spec.id: _withSensitivity(switch ((
          spec.create(deps),
          spec.requiredApp,
        )) {
          (final i, final app?) => AppRequirementGuard(i, app, apps),
          (final i, null) => i,
        }, marks),
  };
});

/// [integration] with the user's „sensibel“ mark from [marks], if it
/// differs from its own.
Integration _withSensitivity(
  Integration integration,
  Map<String, bool> marks,
) => switch (marks[integration.id]) {
  final mark? when mark != integration.sensitive => SensitivityOverride(
    integration,
    sensitive: mark,
  ),
  _ => integration,
};

/// All integrations with their state; decides which tools the model sees.
///
/// In demo mode every integration is on (the ports are in memory);
/// otherwise the stored switches apply.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final registry = ToolRegistry(platform: _appPlatform());
  final holder = ref.read(_currentRegistryProvider)..registry = registry;
  ref.onDispose(() {
    if (identical(holder.registry, registry)) holder.registry = null;
  });
  final demo = ref.watch(demoModeProvider);
  // Read, not watch: switching an integration changes the registry itself.
  final enabled = ref.read(enabledIntegrationsProvider);
  for (final integration in ref.watch(integrationsProvider).values) {
    final on = demo || enabled.contains(integration.id);
    unawaited(
      registry
          .registerIntegration(integration, enabled: on)
          .catchError(_reportRegistrationError),
    );
  }
  // Tool switches and the level for sensitive integrations.
  void apply(ToolPrefs prefs) {
    registry.sensitiveMinimum = prefs.sensitiveMinimum;
    for (final info in registry.integrations) {
      for (final tool in info.integration.tools) {
        registry.setToolEnabled(
          tool.name,
          enabled: !prefs.disabled.contains(tool.name),
        );
      }
    }
  }

  apply(ref.read(toolPrefsProvider));
  ref.listen(toolPrefsProvider, (_, next) => apply(next));
  ref.onDispose(registry.dispose);
  return registry;
});

/// The registry in use, for callbacks of integrations (error state) that
/// cannot depend on [toolRegistryProvider] (it is built from them).
final class _CurrentRegistry {
  ToolRegistry? registry;
}

final _currentRegistryProvider = Provider<_CurrentRegistry>(
  (ref) => _CurrentRegistry(),
);

/// Sources of user-defined integrations (ADR 0012). WP27 (MCP servers) and
/// WP28 (HTTP tools) each add one source here.
final userIntegrationSourcesProvider = Provider<List<UserIntegrationSource>>(
  (ref) => [ref.watch(httpToolSourceProvider)],
);

/// Cleanup after a user-defined integration or some of its tools were
/// removed, besides the secrets its source deletes: forgets the tool
/// switches and confirmations of exactly the removed tools (names from
/// the removed version, not a prefix: `http` and `http_sensitive` both
/// name their tools `http__…`) and, if the whole integration is gone, its
/// „sensibel“ mark and switch.
final userIntegrationCleanupsProvider = Provider<List<IntegrationCleanup>>(
  (ref) => [
    (removal) async {
      final prefs = ref.read(toolPrefsProvider);
      final tools = removal.toolNames;
      final markGone = removal.whole && prefs.sensitive.containsKey(removal.id);
      if (!markGone &&
          !prefs.disabled.any(tools.contains) &&
          !prefs.alwaysConfirm.any(tools.contains)) {
        return;
      }
      await ref
          .read(toolPrefsProvider.notifier)
          .set(
            ToolPrefs(
              disabled: prefs.disabled.difference(tools),
              alwaysConfirm: prefs.alwaysConfirm.difference(tools),
              sensitiveMinimum: prefs.sensitiveMinimum,
              sensitive: {
                for (final e in prefs.sensitive.entries)
                  if (!(removal.whole && e.key == removal.id)) e.key: e.value,
              },
            ),
          );
    },
    (removal) async {
      if (removal.whole) {
        ref
            .read(enabledIntegrationsProvider.notifier)
            .set(removal.id, enabled: false);
      }
    },
  ],
);

/// Keeps the user-defined integrations in the registry
/// ([UserIntegrationSync]); rebuilt together with the registry.
final userIntegrationSyncProvider = Provider<UserIntegrationSync>((ref) {
  final registry = ref.watch(toolRegistryProvider);
  final sync = UserIntegrationSync(
    registry: registry,
    sources: ref.watch(userIntegrationSourcesProvider),
    settings: ref.watch(storageProvider).settings,
    cleanups: ref.watch(userIntegrationCleanupsProvider),
    // Read lazily: a changed mark rebuilds the registry and this sync.
    decorate: (i) => _withSensitivity(i, ref.read(toolPrefsProvider).sensitive),
    onRegistered: (integration) {
      final disabled = ref.read(toolPrefsProvider).disabled;
      for (final tool in integration.tools) {
        registry.setToolEnabled(
          tool.name,
          enabled: !disabled.contains(tool.name),
        );
      }
    },
    onError: (error, stack) => FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'wendelin',
        context: ErrorDescription('bei nutzerdefinierten Integrationen'),
      ),
    ),
  );
  ref.onDispose(sync.dispose);
  return sync;
});

void _reportRegistrationError(Object error, StackTrace stack) =>
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'wendelin',
        context: ErrorDescription('beim Registrieren einer Integration'),
      ),
    );

AppPlatform? _appPlatform() => switch (defaultTargetPlatform) {
  TargetPlatform.android => AppPlatform.android,
  TargetPlatform.iOS => AppPlatform.ios,
  _ => null,
};

/// Ids of the integrations the user switched on (outside the demo mode).
final enabledIntegrationsProvider =
    NotifierProvider<EnabledIntegrations, Set<String>>(EnabledIntegrations.new);

/// Current switches of the integrations; starts with the stored ones.
final class EnabledIntegrations extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(startupProvider).enabledIntegrations;

  /// Records that [id] was switched on or off.
  void set(String id, {required bool enabled}) => state = {
    for (final e in state)
      if (e != id) e,
    if (enabled) id,
  };
}

/// The registry once availability and setup of every integration have been
/// checked. Requests wait for it, so the first one after start sees all
/// active tools.
final toolRegistryReadyProvider = FutureProvider<ToolRegistry>((ref) async {
  final registry = ref.watch(toolRegistryProvider);
  final sync = ref.watch(userIntegrationSyncProvider);
  await registry.refresh();
  await sync.ready;
  return registry;
});

/// Switching integrations on and off (permission first).
final integrationActivatorProvider = Provider<IntegrationActivator>(
  (ref) => IntegrationActivator(
    registry: ref.watch(toolRegistryProvider),
    specs: ref.watch(integrationSpecsProvider),
    deps: ref.watch(integrationDepsProvider),
    settings: ref.watch(storageProvider).settings,
    onChanged: (id, {required enabled}) => ref
        .read(enabledIntegrationsProvider.notifier)
        .set(id, enabled: enabled),
  ),
);

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

/// Audit log writer.
final auditRecorderProvider = Provider<AuditRecorder>(
  (ref) => AuditRecorder(
    ref.watch(storageProvider).audit,
    clock: ref.watch(clockProvider),
  ),
);

/// Current conversation session; ending one forgets unlocked tools and
/// cached calendar data.
final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(
    conversations: ref.watch(storageProvider).conversations,
    clock: ref.watch(clockProvider),
    onSessionEnd: (id) {
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
  return AgentFactory(
    config: AgentConfig(
      userName: assistant.userName,
      personaAddon: assistant.persona,
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
