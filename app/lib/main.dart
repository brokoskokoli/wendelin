import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wendelin_storage/wendelin_storage.dart' show SessionOrigin;

import 'app.dart';
import 'bootstrap/run_app.dart';
import 'bootstrap/storage.dart';
import 'debug/device_test_overrides.dart';
import 'di/agent_providers.dart';
import 'di/maintenance.dart';
import 'platform/recognizer/device_recognizer_engines.dart';
import 'platform/screen_protection.dart';
import 'platform/secure_secret_store.dart';
import 'platform/wake/device_wake_parts.dart';
import 'ui/overlay/assistant_overlay.dart';
import 'ui/theme/app_theme.dart';
import 'voice/voice_log.dart';

export 'bootstrap/device_info.dart' show loadDeviceInfo;
export 'bootstrap/storage.dart' show openAppStorage;

/// Opens the database, reads the start settings and runs the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final (storage, startup) = await openAppStorage();
  await startupMaintenance(
    storage: storage,
    secrets: SecureSecretStore(),
    retentionDays: startup.retentionDays,
  );
  // „Bildschirminhalt schützen“ (the overlay is always protected natively).
  await const ScreenProtection().apply(secure: startup.secureScreen);
  await runWendelinApp(storage, startup, const WendelinApp());
}

/// Entry point of the assistant overlay (`AssistantActivity`, started by
/// the `VoiceInteractionSession` with a transparent window). Runs in its
/// own Flutter engine next to a possibly open main app; both share the
/// database through one drift isolate.
@pragma('vm:entry-point')
Future<void> assistantMain() async {
  voiceLogEngine = 'overlay';
  WidgetsFlutterBinding.ensureInitialized();
  final (storage, startup) = await openAppStorage();
  await runWendelinApp(
    storage,
    startup,
    const AssistantOverlayApp(),
    // Debug builds only: WAV instead of the microphone and a scripted
    // provider for the device tests (WP19); release builds skip this.
    extra: [
      sessionOriginProvider.overrideWithValue(SessionOrigin.overlay),
      if (kDebugMode) ...await deviceTestOverrides(),
    ],
  );
}

/// Entry point of the system speech recognizer (`WendelinRecognitionService`
/// starts it in a headless engine, ADR 0008): Whisper and Silero for other
/// apps, without database, UI or agent.
@pragma('vm:entry-point')
Future<void> recognizerMain() {
  voiceLogEngine = 'recognizer';
  return runRecognizerEngine();
}

/// Entry point of the wake word service (`WakeWordService` starts it in a
/// headless engine, ADR 0013): the feature chain, the templates of all
/// learned voices and, on a candidate, Whisper; without database, UI or
/// agent.
@pragma('vm:entry-point')
Future<void> wakeWordMain() {
  voiceLogEngine = 'wake';
  return runWakeEngine();
}
