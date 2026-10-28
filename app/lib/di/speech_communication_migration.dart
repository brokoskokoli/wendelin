import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';

/// WP165: the setting „Antwort als Gesprächston“ (`voice.speechCommunication`)
/// was removed; the answer always plays in the normal audio context. Deletes
/// the stored value; a no-op without it. Never throws, the next start tries
/// again (a stored value has no effect any more).
Future<void> migrateRemovedSpeechCommunication(
  SettingsRepository settings,
) async {
  try {
    await settings.remove(AppSettings.legacySpeechCommunication);
  } on Object {
    // Try again at the next start.
  }
}
