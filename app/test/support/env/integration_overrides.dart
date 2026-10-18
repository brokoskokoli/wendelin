import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/bring.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/platform/platform_ports.dart';

import '../test_env.dart';

/// Overrides of the integrations: device and demo ports (fakes), Bring!
/// account and sharing.
List<Override> withIntegrations(TestEnv env) => [
  devicePortsProvider.overrideWith(
    (ref) => PlatformPorts(
      calendar: env.calendar,
      clipboard: env.clipboard,
      alarms: env.alarms,
      memory: env.memory,
      apps: env.apps,
      torch: env.torch,
      requestCalendarPermission: env.ports.requestCalendarPermission,
      lists: ListsPorts(
        port: env.listFiles,
        definitions: () => ref.read(listDefinitionsProvider),
      ),
      obsidian: ObsidianPorts(
        vault: env.vault,
        index: env.notes,
        hasVault: () => ref.read(obsidianPrefsProvider).hasVault,
        settings: () =>
            obsidianSettingsOf(ref.read(obsidianPrefsProvider), 'de'),
      ),
    ),
  ),
  if (!env.realDemoPorts) demoPortsProvider.overrideWithValue(env.ports),
  bringApiProvider.overrideWithValue(env.bring),
  haApiProvider.overrideWithValue(env.ha),
  haDiscoveryProvider.overrideWithValue(env.haDiscovery),
  appShareProvider.overrideWithValue(
    (package, text) async => env.shared.add((package, text)),
  ),
];
