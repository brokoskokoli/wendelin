import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../l10n/l10n.dart';
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
    this.setupWizardDone = true,
    this.setupWizardPage,
    this.language = 'de',
    this.uiLanguage = 'system',
    this.developerMode = false,
    this.assistant = const AssistantPrefs(),
    this.retentionDays = 30,
    this.toolPrefs = const ToolPrefs(),
    this.webSearch,
    this.weather = const WeatherConfig(),
    this.lists = const [],
    this.obsidian = const ObsidianPrefs(),
    this.secureScreen = false,
    this.haFastPath = true,
    this.navigationApp,
    this.station = const StationPrefs(),
  });

  /// Integrations the user switched on.
  final Set<String> enabledIntegrations;

  /// Debug demo mode.
  final bool demoMode;

  /// Show reasoning text.
  final bool showThinking;

  /// Whether the setup wizard (WP174) is finished (`true` by default so tests
  /// and the demo start on the main screen; [load] reads the stored value,
  /// missing = not done).
  final bool setupWizardDone;

  /// Stored page name of the wizard (`SetupPage.name`), `null` = start.
  final String? setupWizardPage;

  /// Preferred language.
  final String language;

  /// App UI language: `system`, `de`, `en`, `fr`.
  final String uiLanguage;

  /// Developer mode (WP148).
  final bool developerMode;

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

  /// Chosen navigation app (`NavigationApp.id`), `null` = default (WP164 B).
  final String? navigationApp;

  /// Station mode settings (WP99).
  final StationPrefs station;

  /// Reads the settings for the integrations [integrationIds]. Without a
  /// stored choice, [language] follows the system language ([systemLocales],
  /// default: the platform's): `de`/`en`/`fr`, anything else `en`.
  static Future<StartupSettings> load(
    SettingsRepository settings,
    Iterable<String> integrationIds, {
    List<Locale>? systemLocales,
  }) async {
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
      setupWizardDone: await settings.get(AppSettings.setupWizardDone) ?? false,
      setupWizardPage: await settings.get(AppSettings.setupWizardPage),
      language:
          await settings.get(AppSettings.language) ??
          systemLanguageCode(
            systemLocales ?? PlatformDispatcher.instance.locales,
          ),
      uiLanguage: await settings.get(AppSettings.uiLanguage) ?? 'system',
      developerMode: await settings.get(AppSettings.developerMode) ?? false,
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
      navigationApp: await settings.get(AppSettings.navigationApp),
      station: await settings.get(AppSettings.station) ?? const StationPrefs(),
    );
  }
}
