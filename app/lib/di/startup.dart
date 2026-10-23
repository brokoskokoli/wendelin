import 'package:flutter/foundation.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../station/station_prefs.dart';
import 'app_settings.dart';
import 'preference_models.dart';
import 'weather_config.dart';

/// Settings read once before the first frame.
@immutable
final class StartupSettings {
  /// Creates the settings.
  const StartupSettings({
    this.enabledIntegrations = const {},
    this.demoMode = false,
    this.showThinking = false,
    this.onboardingDone = true,
    this.language = 'de',
    this.uiLanguage = 'system',
    this.assistant = const AssistantPrefs(),
    this.retentionDays = 30,
    this.toolPrefs = const ToolPrefs(),
    this.webSearch,
    this.weather = const WeatherConfig(),
    this.lists = const [],
    this.obsidian = const ObsidianPrefs(),
    this.secureScreen = false,
    this.haFastPath = true,
    this.station = const StationPrefs(),
  });

  /// Integrations the user switched on.
  final Set<String> enabledIntegrations;

  /// Debug demo mode.
  final bool demoMode;

  /// Show reasoning text.
  final bool showThinking;

  /// Whether the onboarding is done (`true` by default so tests and the
  /// demo start on the main screen; [load] reads the stored value).
  final bool onboardingDone;

  /// Preferred language.
  final String language;

  /// App UI language: `system`, `de`, `en`, `fr`.
  final String uiLanguage;

  /// Name and persona.
  final AssistantPrefs assistant;

  /// Retention of logs and conversations in days.
  final int retentionDays;

  /// Tool switches and confirmations.
  final ToolPrefs toolPrefs;

  /// Web search service.
  final WebSearchConfig? webSearch;

  /// Weather service and home place.
  final WeatherConfig weather;

  /// The user's lists.
  final List<ListDefinition> lists;

  /// Obsidian vault and daily notes.
  final ObsidianPrefs obsidian;

  /// Protect the main app's screen content.
  final bool secureScreen;

  /// Simple Home Assistant commands without a model (WP135 D).
  final bool haFastPath;

  /// Station mode settings (WP99).
  final StationPrefs station;

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
      onboardingDone: await settings.get(AppSettings.onboardingDone) ?? false,
      language: await settings.get(AppSettings.language) ?? 'de',
      uiLanguage: await settings.get(AppSettings.uiLanguage) ?? 'system',
      assistant: AssistantPrefs(
        userName: await settings.get(AppSettings.userName),
        persona: await settings.get(AppSettings.persona),
      ),
      retentionDays: await settings.get(AppSettings.retentionDays) ?? 30,
      toolPrefs: await settings.get(AppSettings.toolPrefs) ?? const ToolPrefs(),
      webSearch: await settings.get(AppSettings.webSearch),
      weather: await settings.get(AppSettings.weather) ?? const WeatherConfig(),
      lists: await settings.get(AppSettings.lists) ?? const [],
      obsidian:
          await settings.get(AppSettings.obsidian) ?? const ObsidianPrefs(),
      secureScreen: await settings.get(AppSettings.secureScreen) ?? false,
      haFastPath: await settings.get(AppSettings.haFastPath) ?? true,
      station: await settings.get(AppSettings.station) ?? const StationPrefs(),
    );
  }
}
