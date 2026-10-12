import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import 'app_settings.dart';
import 'integration_specs.dart';

/// Switches integrations on and off. The OS permission of an integration
/// is requested here, when the user enables it, and never at app start
/// (concept: „Berechtigungen“).
final class IntegrationActivator {
  /// Creates the activator.
  IntegrationActivator({
    required this.registry,
    required List<IntegrationSpec> specs,
    required this.deps,
    required this.settings,
    this.onChanged,
  }) : _specs = {for (final s in specs) s.id: s};

  /// The registry whose switches are changed.
  final ToolRegistry registry;

  /// Dependencies passed to the permission requests.
  final IntegrationDeps deps;

  /// Where the switches are stored.
  final SettingsRepository settings;

  /// Told about every switch change (keeps the app state in sync).
  final void Function(String id, {required bool enabled})? onChanged;

  final Map<String, IntegrationSpec> _specs;

  /// Switches [id] on or off and returns its new status. Enabling first
  /// asks for the permission; if it is denied the integration is still on,
  /// but shows „Einrichtung nötig“ until [setUp] succeeds.
  Future<IntegrationStatus> setEnabled(
    String id, {
    required bool enabled,
  }) async {
    if (enabled) await _requestPermission(id);
    registry.setEnabled(id, enabled: enabled);
    await settings.set(AppSettings.integrationEnabled(id), enabled);
    onChanged?.call(id, enabled: enabled);
    await registry.refresh(id);
    return registry.status(id);
  }

  /// Runs the missing setup of [id] again (e.g. permission) and returns its
  /// status.
  Future<IntegrationStatus> setUp(String id) async {
    await _requestPermission(id);
    await registry.refresh(id);
    return registry.status(id);
  }

  Future<void> _requestPermission(String id) async {
    final request = _specs[id]?.requestPermission;
    if (request != null) await request(deps);
  }
}
