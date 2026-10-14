import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'app_settings.dart';

/// [UserIntegrationRegistry] on the app's [ToolRegistry].
final class ToolRegistryUserIntegrations implements UserIntegrationRegistry {
  /// Creates the adapter.
  const ToolRegistryUserIntegrations(this.registry);

  /// The registry the integrations go into.
  final ToolRegistry registry;

  @override
  bool isEnabled(String id) => registry.info(id).enabled;

  @override
  Future<void> register(Integration integration, {required bool enabled}) =>
      registry.registerIntegration(integration, enabled: enabled);

  @override
  void unregister(String id) => registry.unregister(id);
}

/// [UserIntegrationSwitches] on the settings
/// (`AppSettings.integrationEnabled`).
final class SettingsUserIntegrationSwitches implements UserIntegrationSwitches {
  /// Creates the adapter.
  const SettingsUserIntegrationSwitches(this.settings);

  /// Where the switches are stored.
  final SettingsRepository settings;

  @override
  Future<bool?> stored(String id) =>
      settings.get(AppSettings.integrationEnabled(id));

  @override
  Future<void> forget(String id) =>
      settings.remove(AppSettings.integrationEnabled(id));
}
