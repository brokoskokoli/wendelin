import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app.dart';
import 'debug/device_test_overrides.dart';
import 'di/integration_specs.dart';
import 'di/maintenance.dart';
import 'di/providers.dart';
import 'di/startup.dart';
import 'platform/recognizer/device_recognizer_engines.dart';
import 'platform/screen_protection.dart';
import 'platform/secure_secret_store.dart';
import 'ui/overlay/assistant_overlay.dart';
import 'ui/theme/app_theme.dart';
import 'voice/voice_log.dart';

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
  await _run(storage, startup, const WendelinApp());
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
  await _run(
    storage,
    startup,
    const AssistantOverlayApp(),
    // Debug builds only: WAV instead of the microphone and a scripted
    // provider for the device tests (WP19); release builds skip this.
    extra: kDebugMode ? await deviceTestOverrides() : const [],
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

/// Opens the app database (shared with the other engine of the process)
/// and reads the start settings.
Future<(WendelinStorage, StartupSettings)> openAppStorage() async {
  // Shared across isolates: the overlay engine and the main app may run
  // at the same time in one process.
  final storage = WendelinStorage(
    driftDatabase(
      name: 'wendelin',
      native: const DriftNativeOptions(shareAcrossIsolates: true),
    ),
  );
  final startup = await StartupSettings.load(storage.settings, [
    for (final s in builtInIntegrationSpecs) s.id,
  ]);
  return (storage, startup);
}

Future<void> _run(
  WendelinStorage storage,
  StartupSettings startup,
  Widget app, {
  List<Override> extra = const [],
}) async {
  final device = await loadDeviceInfo();
  runApp(
    ProviderScope(
      // Failures are shown, not retried in the background.
      retry: (_, _) => null,
      overrides: [
        storageProvider.overrideWithValue(storage),
        startupProvider.overrideWithValue(startup),
        deviceInfoProvider.overrideWithValue(device),
        ...extra,
      ],
      child: app,
    ),
  );
}

/// Locale (BCP 47) and IANA time zone of the device.
Future<DeviceInfo> loadDeviceInfo() async {
  final locale = PlatformDispatcher.instance.locale.toLanguageTag();
  String zone;
  try {
    zone = (await FlutterTimezone.getLocalTimezone()).identifier;
  } on Object catch (e) {
    if (e is! PlatformException &&
        e is! MissingPluginException &&
        e is! ArgumentError) {
      rethrow;
    }
    // No IANA name available: UTC keeps instants correct, only the shown
    // local times are off. Logged so it does not go unnoticed.
    debugPrint('Zeitzone nicht lesbar, verwende UTC: $e');
    zone = 'UTC';
  }
  return DeviceInfo(locale: locale, timeZone: zone);
}
