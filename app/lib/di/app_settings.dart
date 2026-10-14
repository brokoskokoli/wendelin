import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'preference_models.dart';

/// Settings keys of the app (stored in `SettingsRepository`).
///
/// WP09 (settings screens) writes most of them; the app shell reads them.
abstract final class AppSettings {
  /// Debug only: demo mode with the scripted provider and in-memory ports.
  static final demoMode = SettingKey.boolean(
    'debug.demoMode',
    defaultValue: false,
  );

  /// Show reasoning text of the model in the conversation (off by default).
  static final showThinking = SettingKey.boolean(
    'chat.showThinking',
    defaultValue: false,
  );

  /// Calendar for new events, chosen by the user (device calendar id).
  static final defaultCalendarId = SettingKey.string('calendar.defaultId');

  /// M2 escalation chain after the default profile (profile ids, weakest
  /// first). Since M3 only read once, when `loadRuleSet` migrates it into
  /// the routing rules (`RoutingSettings.rules`).
  static final escalationChain = SettingKey<List<String>>(
    'routing.escalationChain',
    encode: (ids) => ids,
    decode: (json) {
      if (json is List && json.every((e) => e is String)) {
        return json.cast<String>();
      }
      throw const FormatException('routing.escalationChain: Liste erwartet');
    },
    defaultValue: const [],
  );

  /// Whether the integration [id] is switched on.
  static SettingKey<bool> integrationEnabled(String id) =>
      SettingKey.boolean('integration.$id.enabled', defaultValue: false);

  /// Onboarding finished (or skipped).
  static final onboardingDone = SettingKey.boolean(
    'onboarding.done',
    defaultValue: false,
  );

  /// Preferred language (`de`, `fr`, `en`); the UI is German for now.
  static final language = SettingKey.string('app.language', defaultValue: 'de');

  /// How the assistant addresses the user.
  static final userName = SettingKey.string('assistant.userName');

  /// Persona addition to the system prompt.
  static final persona = SettingKey.string('assistant.persona');

  /// Protect the main app's screen content (`FLAG_SECURE`), off by default.
  static final secureScreen = SettingKey.boolean(
    'privacy.secureScreen',
    defaultValue: false,
  );

  /// GPU check of TEE models at NVIDIA: `off` (default), `before`, `after`
  /// (name of `GpuCheckMode`).
  static final gpuCheck = SettingKey.string(
    'tee.gpuCheck',
    defaultValue: 'off',
  );

  /// Pin of the attested TEE provider [profileId] (JSON of `AttestationPin`).
  static SettingKey<Map<String, Object?>> attestationPin(String profileId) =>
      SettingKey.json('tee.pin.$profileId');

  /// Retention of audit log and conversations in days (concept: 30).
  static final retentionDays = SettingKey.integer(
    'privacy.retentionDays',
    defaultValue: 30,
  );

  /// Tool switches, confirmations and the level for sensitive integrations.
  static final toolPrefs = SettingKey<ToolPrefs>(
    'tools.prefs',
    encode: (p) => p.toJson(),
    decode: (json) {
      if (json is Map<String, Object?>) return ToolPrefs.fromJson(json);
      throw const FormatException('tools.prefs: Objekt erwartet');
    },
    defaultValue: const ToolPrefs(),
  );

  /// Configured web search service (key in the SecretStore).
  static final webSearch = SettingKey<WebSearchConfig>(
    'web.search',
    encode: (c) => c.toJson(),
    decode: (json) {
      if (json is Map<String, Object?>) return WebSearchConfig.fromJson(json);
      throw const FormatException('web.search: Objekt erwartet');
    },
  );

  /// The user's lists (K6).
  static final lists = SettingKey<List<ListDefinition>>(
    'lists.definitions',
    encode: (lists) => [for (final l in lists) listDefinitionToJson(l)],
    decode: (json) {
      if (json is! List) throw const FormatException('lists: Liste erwartet');
      return [for (final e in json) listDefinitionFromJson(e)];
    },
    defaultValue: const [],
  );

  /// Obsidian vault and daily notes.
  static final obsidian = SettingKey<ObsidianPrefs>(
    'obsidian.prefs',
    encode: (p) => p.toJson(),
    decode: (json) {
      if (json is Map<String, Object?>) return ObsidianPrefs.fromJson(json);
      throw const FormatException('obsidian.prefs: Objekt erwartet');
    },
    defaultValue: const ObsidianPrefs(),
  );
}
