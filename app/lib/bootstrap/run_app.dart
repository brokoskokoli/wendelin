import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/providers.dart';
import '../di/startup.dart';
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
