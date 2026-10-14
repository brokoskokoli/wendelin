import 'package:drift_flutter/drift_flutter.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/integration_specs.dart';
import '../di/startup.dart';

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
