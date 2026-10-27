import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wendelin/di/bring.dart';
import 'package:wendelin/di/google_tasks.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/spotify.dart';
import 'package:wendelin/di/todoist.dart';
import 'package:wendelin/platform/platform_ports.dart';

import '../test_env.dart';

/// One shared function: a fresh closure per call would differ in the
/// integration deps (record equality) and rebuild the registry.
Future<void> _noDelay(Duration _) async {}

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
      station: env.station,
      media: env.media,
      contacts: env.contacts,
      phone: env.phone,
      location: env.location,
      mapsLauncher: env.mapsLauncher,
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
  todoistApiProvider.overrideWithValue(env.todoist),
  googleTasksApiProvider.overrideWithValue(env.googleTasks),
  googleOAuthProvider.overrideWithValue(env.googleTasks),
  googleBrowserProvider.overrideWithValue(env.googleBrowser),
  googleReceiverProvider.overrideWithValue(() async => env.googleReceiver),
  haApiProvider.overrideWithValue(env.ha),
  haDiscoveryProvider.overrideWithValue(env.haDiscovery),
  spotifyApiProvider.overrideWithValue(env.spotify),
  spotifyAuthBrowserProvider.overrideWithValue(env.spotifyBrowser),
  spotifyLauncherProvider.overrideWithValue(env.spotifyLauncher),
  spotifyHostDeviceProvider.overrideWithValue(env.spotifyHostDevice),
  // Checks of „spotify__play“ do not wait in real time.
  spotifyDelayProvider.overrideWithValue(_noDelay),
  appShareProvider.overrideWithValue(
    (package, text) async => env.shared.add((package, text)),
  ),
];
