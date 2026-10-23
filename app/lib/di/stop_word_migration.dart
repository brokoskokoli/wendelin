import 'package:wendelin_storage/wendelin_storage.dart';

import 'voice_settings_providers.dart';

/// Prefix of the removed „Stopp“ templates (`wake.stop.<speakerId>`).
const legacyStopPrefix = 'wake.stop.';

/// Key of the removed setting „Stopp schließt das Overlay“ in the stored
/// voice settings (`voice.settings`).
const legacyStopClosesOverlay = 'stopClosesOverlay';

/// WP134: the spoken „Stopp“ (barge-in) was removed. Deletes the stored
/// „Stopp“ templates from the [secrets] and the setting
/// `stopClosesOverlay` from the stored voice settings; a no-op without them.
/// Never throws: a damaged or missing entry is skipped, the next start
/// tries again.
Future<void> migrateRemovedStopWord(
  SettingsRepository settings,
  SecretStore secrets,
) async {
  try {
    for (final key in await secrets.listKeys()) {
      if (key.startsWith(legacyStopPrefix)) await secrets.delete(key);
    }
  } on Object {
    // Try again at the next start; the templates are not used any more.
  }
  try {
    final raw = await settings.get(_rawVoiceSettings);
    if (raw == null || !raw.containsKey(legacyStopClosesOverlay)) return;
    await settings.set(_rawVoiceSettings, {...raw}..remove(legacyStopClosesOverlay));
  } on Object {
    // Damaged settings: the normal loading falls back to the defaults.
  }
}

// Same key as [voiceSettingsKey], but the stored JSON as it is.
final _rawVoiceSettings = SettingKey<Map<String, Object?>>(
  voiceSettingsKey.name,
  encode: (m) => m,
  decode: (json) {
    if (json is Map<String, Object?>) return json;
    throw const FormatException('voice.settings: Objekt erwartet');
  },
);
