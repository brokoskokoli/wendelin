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
import 'app_settings.dart';
import 'audit_recorder.dart';
import 'costs.dart';
import 'integration_activator.dart';
import 'integration_specs.dart';
import 'provider_config.dart';
import 'session_manager.dart';
import 'startup.dart';

// Riverpod wiring of the app. `main.dart` overrides [storageProvider],
// [startupProvider] and [deviceInfoProvider]; tests also override the ports
// and the provider configuration.

/// Time source.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

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
  (ref) => PlatformPorts.device(ref.watch(storageProvider)),
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
final integrationDepsProvider = Provider<IntegrationDeps>(
  (ref) => IntegrationDeps(
    ports: ref.watch(platformPortsProvider),
    device: ref.watch(deviceInfoProvider),
    httpClient: ref.watch(httpClientProvider),
  ),
);

/// The built integrations by id.
final integrationsProvider = Provider<Map<String, Integration>>((ref) {
  final deps = ref.watch(integrationDepsProvider);
  return {
    for (final spec in ref.watch(integrationSpecsProvider))
      if (spec.isSupported?.call(deps) ?? true) spec.id: spec.create(deps),
  };
});

/// All integrations with their state; decides which tools the model sees.
///
/// In demo mode every integration is on (the ports are in memory);
/// otherwise the stored switches apply.
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final registry = ToolRegistry(platform: _appPlatform());
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
  ref.onDispose(registry.dispose);
  return registry;
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
  await registry.refresh();
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

/// Risk policy (per-tool overrides come with WP09).
final riskPolicyProvider = Provider<RiskPolicy>((ref) => RiskPolicy());

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
        if (integration != null) spec.onSessionEnd?.call(integration);
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

/// The configuration from the stored profiles. Invalidate after profiles
/// or the escalation chain changed (WP09).
final storedProviderConfigProvider = FutureProvider<ProviderConfig?>(
  (ref) => loadProviderConfig(
    storage: ref.watch(storageProvider),
    secrets: ref.watch(secretStoreProvider),
    catalog: ref.watch(modelCatalogProvider),
  ),
);

/// Builds the agent for each request.
final agentFactoryProvider = Provider<AgentRunFactory>((ref) {
  final storage = ref.watch(storageProvider);
  return AgentFactory(
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
