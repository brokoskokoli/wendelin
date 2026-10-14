import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/providers.dart';
import '../di/startup.dart';
import '../di/voice_providers.dart';
import '../di/wake_providers.dart';
import 'device_info.dart';

/// Runs [app] in a `ProviderScope` with the overrides every engine needs
/// (database, start settings, device); [extra] adds more.
Future<void> runWendelinApp(
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
      overrides: [...engineOverrides(storage, startup, device), ...extra],
      child: app,
    ),
  );
}

/// The overrides every engine needs: database, start settings, device.
List<Override> engineOverrides(
  WendelinStorage storage,
  StartupSettings startup,
  DeviceInfo device,
) => [
  storageProvider.overrideWithValue(storage),
  startupProvider.overrideWithValue(startup),
  deviceInfoProvider.overrideWithValue(device),
  // Barge-in on the wake word chain (WP50); null without conversation mode.
  bargeInDetectorProvider.overrideWith(
    (ref) => ref.watch(wakeBargeInDetectorProvider),
  ),
];
