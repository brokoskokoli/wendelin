import 'package:flutter/foundation.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';

/// Settings read once before the first frame.
@immutable
final class StartupSettings {
  /// Creates the settings.
  const StartupSettings({
    this.enabledIntegrations = const {},
    this.demoMode = false,
    this.showThinking = false,
  });

  /// Integrations the user switched on.
  final Set<String> enabledIntegrations;

  /// Debug demo mode.
  final bool demoMode;

  /// Show reasoning text.
  final bool showThinking;

  /// Reads the settings for the integrations [integrationIds].
  static Future<StartupSettings> load(
    SettingsRepository settings,
    Iterable<String> integrationIds,
  ) async {
    final enabled = <String>{};
    for (final id in integrationIds) {
      if (await settings.get(AppSettings.integrationEnabled(id)) ?? false) {
        enabled.add(id);
      }
    }
    return StartupSettings(
      enabledIntegrations: enabled,
      demoMode: await settings.get(AppSettings.demoMode) ?? false,
      showThinking: await settings.get(AppSettings.showThinking) ?? false,
    );
  }
}
