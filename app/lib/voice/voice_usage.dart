import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/providers.dart';
import 'voice_log.dart';

// Base load (WP30 review): the main screen loads Whisper ahead only for
// people who actually talk to Wendelin. Only a timestamp is stored, never
// what was said.

/// When a voice request last started (milliseconds since the epoch, UTC).
final voiceLastUseKey = SettingKey<DateTime>(
  'voice.lastUse',
  encode: (t) => t.toUtc().millisecondsSinceEpoch,
  decode: (json) {
    if (json is int) {
      return DateTime.fromMillisecondsSinceEpoch(json, isUtc: true);
    }
    throw const FormatException('voice.lastUse: Zahl erwartet');
  },
);

/// How long after the last voice request the main screen still warms up
/// the speech models.
final voiceRecentUseProvider = Provider<Duration>(
  (ref) => const Duration(hours: 24),
);

/// Stores that speech was used now; failures only go to the log.
Future<void> noteVoiceUse(Ref ref) async {
  try {
    await ref
        .read(storageProvider)
        .settings
        .set(voiceLastUseKey, ref.read(clockProvider).now());
  } on Object catch (e) {
    voiceLog('usage-failed', {'error': errorCode(e)});
  }
}

/// Whether speech was used within [voiceRecentUseProvider].
Future<bool> voiceUsedRecently(Ref ref) async {
  try {
    final last = await ref.read(storageProvider).settings.get(voiceLastUseKey);
    if (last == null) return false;
    final age = ref.read(clockProvider).now().difference(last);
    return age <= ref.read(voiceRecentUseProvider);
  } on Object catch (e) {
    voiceLog('usage-failed', {'error': errorCode(e)});
    return false;
  }
}
