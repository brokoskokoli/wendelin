// Integration providers: specs, dependencies, built integrations, installed
// apps, tool registry, user-defined integrations and the activator
// (extension point: `integrations/registry.dart`). Imported via
// `providers.dart`.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'app_requirements.dart';
import 'core_providers.dart';
import 'http_tools.dart';
import 'integration_activator.dart';
import 'integration_specs.dart';
import 'mcp/mcp_providers.dart';
import 'preference_models.dart';
import 'preferences.dart';
import 'sensitivity.dart';
import 'user_integrations.dart';

/// Registered integrations (extension point, see [IntegrationSpec]).
final integrationSpecsProvider = Provider<List<IntegrationSpec>>(
  (ref) => builtInIntegrationSpecs,
);

/// Dependencies for building integrations.
final integrationDepsProvider = Provider<IntegrationDeps>((ref) {
  // The registry is built from these integrations, so it is reached
  // through a holder instead of a provider dependency.
  final holder = ref.watch(_currentRegistryProvider);
  void onRegistry(String id, void Function(ToolRegistry registry) action) {
    final registry = holder.registry;
    if (registry == null) return;
    if (registry.integrations.any((i) => i.id == id)) action(registry);
  }

  final specs = ref.watch(integrationSpecsProvider);
  return IntegrationDeps(
    reportError: (id, message, kind) =>
        onRegistry(id, (r) => r.reportError(id, message, kind: kind)),
    clearError: (id) => onRegistry(id, (r) => r.clearError(id)),
    ports: ref.watch(platformPortsProvider),
    device: ref.watch(deviceInfoProvider),
    httpClient: ref.watch(httpClientProvider),
    // What each spec needs besides the common dependencies.
    extras: {
      for (final spec in specs)
        if (spec.prepare != null) spec.id: spec.prepare!(ref),
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
  (ref) => [
    ref.watch(mcpServerSourceProvider),
    ref.watch(httpToolSourceProvider),
  ],
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
      // A deleted MCP server: every stored level of its tools goes, also of
      // tools that were not known at deletion (server offline, renamed): a
      // new server with the same slug must not inherit a looser level.
      final prefix = removal.whole && removal.id.startsWith('mcp_')
          ? '${removal.id}__'
          : null;
      bool levelGone(String tool) =>
          tools.contains(tool) || (prefix != null && tool.startsWith(prefix));
      final markGone = removal.whole && prefs.sensitive.containsKey(removal.id);
      if (!markGone &&
          !prefs.disabled.any(tools.contains) &&
          !prefs.alwaysConfirm.any(tools.contains) &&
          !prefs.levels.keys.any(levelGone)) {
        return;
      }
      await ref
          .read(toolPrefsProvider.notifier)
          .set(
            ToolPrefs(
              disabled: prefs.disabled.difference(tools),
              alwaysConfirm: prefs.alwaysConfirm.difference(tools),
              levels: {
                for (final e in prefs.levels.entries)
                  if (!levelGone(e.key)) e.key: e.value,
              },
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
    registry: ToolRegistryUserIntegrations(registry),
    sources: ref.watch(userIntegrationSourcesProvider),
    switches: SettingsUserIntegrationSwitches(
      ref.watch(storageProvider).settings,
    ),
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
