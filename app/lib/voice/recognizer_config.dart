import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/preferences.dart';
import '../di/voice_providers.dart';
import '../platform/assistant_platform.dart';

/// The speech settings for the system recognizer (WP20): Whisper model,
/// language („Wie die App“ resolved), Silero threshold and minimum speech
/// duration from Einstellungen → Sprache; `null` while they load.
final recognizerConfigProvider = Provider<RecognizerConfig?>((ref) {
  final s = ref.watch(voiceSettingsProvider).value;
  if (s == null) return null;
  return RecognizerConfig(
    model: s.sttModel,
    language: s.effectiveLanguage(ref.watch(languageProvider)),
    vadThreshold: s.vadThreshold,
    minSpeechMs: s.minSpeechMs,
  );
});

/// Mirrors [recognizerConfigProvider] to the recognizer service at start
/// and on every change (the service has no database access, ADR 0008).
/// Watched by the main app.
final recognizerConfigSyncProvider = Provider<void>((ref) {
  ref.listen(recognizerConfigProvider, (previous, next) {
    if (next == null || next == previous) return;
    unawaited(ref.read(assistantPlatformProvider).setRecognizerConfig(next));
  }, fireImmediately: true);
});

/// Whether Wendelin offers itself as speech recognizer to other apps
/// (Einstellungen → Assistent).
final recognizerOfferedProvider =
    AsyncNotifierProvider<RecognizerOfferedNotifier, bool>(
      RecognizerOfferedNotifier.new,
    );

/// „Als Spracherkennung für andere Apps anbieten“.
final class RecognizerOfferedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(assistantPlatformProvider).isRecognizerOffered();

  /// Turns the offer on or off.
  Future<void> set({required bool offered}) async {
    state = AsyncData(offered);
    await ref
        .read(assistantPlatformProvider)
        .setRecognizerOffered(offered: offered);
  }
}
