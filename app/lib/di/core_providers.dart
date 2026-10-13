// Core providers: clock, ids, storage, startup, device, secrets, HTTP, URL
// launcher, demo mode and the ports in use. `main.dart` overrides
// [storageProvider], [startupProvider] and [deviceInfoProvider]; tests also
// override the ports. Imported via `providers.dart`.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin_agent/wendelin_agent.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_providers/wendelin_providers.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/platform_ports.dart';
import '../platform/secure_secret_store.dart';
import 'app_settings.dart';
import 'preferences.dart';
import 'startup.dart';

/// Time source.
final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Ids for profiles, lists and key references.
final idGeneratorProvider = Provider<IdGenerator>((ref) => UuidV4Generator());

/// Local database; overridden in `main.dart` (drift_flutter) and in tests
/// (in-memory).
final storageProvider = Provider<WendelinStorage>(
  (ref) => throw UnimplementedError('storageProvider muss gesetzt werden'),
);

/// Settings read once at start.
final startupProvider = Provider<StartupSettings>(
  (ref) => const StartupSettings(),
);

/// Locale and IANA time zone of the device; overridden in `main.dart`.
final deviceInfoProvider = Provider<DeviceInfo>(
  (ref) => const DeviceInfo(locale: 'de-DE', timeZone: 'Europe/Berlin'),
);

/// Secrets (Android Keystore).
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

/// Shared HTTP client for integrations.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Opens web addresses (download page of a missing app); throws a
/// `PortException` if nothing can open it.
final urlLauncherProvider = Provider<Future<void> Function(Uri url)>(
  (ref) => openExternalUrl,
);

/// Model prices.
final modelCatalogProvider = Provider<ModelCatalog>(
  (ref) => ModelCatalog.builtIn(),
);

/// Debug demo mode (scripted provider, in-memory ports). Always off in
/// release builds.
final demoModeProvider = NotifierProvider<DemoModeNotifier, bool>(
  DemoModeNotifier.new,
);

/// Switches the demo mode and stores the choice.
final class DemoModeNotifier extends Notifier<bool> {
  @override
  bool build() => kDebugMode && ref.watch(startupProvider).demoMode;

  /// Switches the demo mode on or off (no effect in release builds).
  Future<void> set({required bool enabled}) async {
    if (!kDebugMode) return;
    state = enabled;
    await ref.read(storageProvider).settings.set(AppSettings.demoMode, enabled);
  }
}

/// Ports of the real device.
final devicePortsProvider = Provider<PlatformPorts>(
  (ref) => PlatformPorts.device(
    ref.watch(storageProvider),
    listDefinitions: () => ref.read(listDefinitionsProvider),
    obsidian: () => ref.read(obsidianPrefsProvider),
    language: () => ref.read(languageProvider),
  ),
);

/// In-memory ports of the demo mode.
final demoPortsProvider = Provider<PlatformPorts>(
  (ref) => PlatformPorts.demo(),
);

/// Ports in use (demo or device).
final platformPortsProvider = Provider<PlatformPorts>(
  (ref) => ref.watch(demoModeProvider)
      ? ref.watch(demoPortsProvider)
      : ref.watch(devicePortsProvider),
);
