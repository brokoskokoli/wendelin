import 'package:drift_flutter/drift_flutter.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/gpu_check_migration.dart';
import '../di/integration_specs.dart';
import '../di/speech_communication_migration.dart';
import '../di/startup.dart';
import '../di/stop_word_migration.dart';
import '../platform/secure_secret_store.dart';

/// The start migrations of the stored settings (each never throws and is
/// idempotent). Called by [openAppStorage] at every start.
Future<void> runSettingsMigrations(
  WendelinStorage storage,
  SecretStore secrets,
) async {
  await migrateGlobalGpuCheck(storage.settings, storage.providerProfiles);
  await migrateRemovedStopWord(storage.settings, secrets);
  await migrateRemovedSpeechCommunication(storage.settings);
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
  await runSettingsMigrations(storage, SecureSecretStore());
  final startup = await StartupSettings.load(storage.settings, [
    for (final s in builtInIntegrationSpecs) s.id,
  ]);
  return (storage, startup);
}
