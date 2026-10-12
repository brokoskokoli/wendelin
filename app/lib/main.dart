import 'dart:ui';

import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app.dart';
import 'di/integration_specs.dart';
import 'di/providers.dart';
import 'di/startup.dart';
import 'ui/theme/app_theme.dart';

/// Opens the database, reads the start settings and runs the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final storage = WendelinStorage(driftDatabase(name: 'wendelin'));
  final startup = await StartupSettings.load(storage.settings, [
    for (final s in builtInIntegrationSpecs) s.id,
  ]);
  final device = await loadDeviceInfo();
  runApp(
    ProviderScope(
      // Failures are shown, not retried in the background.
      retry: (_, _) => null,
      overrides: [
        storageProvider.overrideWithValue(storage),
        startupProvider.overrideWithValue(startup),
        deviceInfoProvider.overrideWithValue(device),
      ],
      child: const WendelinApp(),
    ),
  );
}

/// Locale (BCP 47) and IANA time zone of the device.
Future<DeviceInfo> loadDeviceInfo() async {
  final locale = PlatformDispatcher.instance.locale.toLanguageTag();
  String zone;
  try {
    zone = (await FlutterTimezone.getLocalTimezone()).identifier;
  } on PlatformException {
    // No IANA name available: UTC keeps times correct, only less friendly.
    zone = 'UTC';
  }
  return DeviceInfo(locale: locale, timeZone: zone);
}
