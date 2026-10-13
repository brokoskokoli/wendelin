import 'package:wendelin_storage/wendelin_storage.dart';

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

  /// Escalation chain after the default profile: profile ids, weakest first.
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
}
