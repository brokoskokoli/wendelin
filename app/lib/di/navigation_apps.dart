import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'preferences.dart';
import 'providers.dart';

/// Integration id of a navigation app (WP164 B).
String navigationIntegrationId(NavigationApp app) => switch (app) {
  NavigationApp.googleMaps => 'maps',
  NavigationApp.waze => 'waze',
};

/// [NavigationApps] over the integration switches, the app detection and
/// the setting „Navigations-App“. Everything is read per call, so a switch
/// or a new choice applies to the next request.
final class AppNavigationApps implements NavigationApps {
  /// Creates the adapter.
  AppNavigationApps({
    required this.enabledIntegrations,
    required this.knownInstalled,
    required this.preference,
    required this.presence,
  });

  /// Ids of the integrations that are on (all of them in demo mode).
  final Set<String> Function() enabledIntegrations;

  /// Last known answer of the app detection for a package (`null` =
  /// unknown).
  final bool? Function(String androidPackage) knownInstalled;

  /// The chosen app, `null` = default.
  final NavigationApp? Function() preference;

  /// Live app detection.
  final AppPresencePort presence;

  @override
  Set<NavigationApp> get active {
    final on = enabledIntegrations();
    return {
      for (final app in NavigationApp.values)
        if (on.contains(navigationIntegrationId(app)) &&
            knownInstalled(app.package) == true)
          app,
    };
  }

  @override
  NavigationApp? get preferred => preference();

  @override
  Future<bool> isInstalled(NavigationApp app) =>
      presence.isInstalled(app.package);
}

/// The navigation apps as the app sees them now, for `maps__navigate` and
/// `contacts__navigate` (WP164 C). In demo mode all apps count as on.
AppNavigationApps appNavigationApps(Ref ref) => AppNavigationApps(
  enabledIntegrations: () => ref.read(demoModeProvider)
      ? {for (final a in NavigationApp.values) navigationIntegrationId(a)}
      : ref.read(enabledIntegrationsProvider),
  knownInstalled: (package) => ref.read(installedAppsProvider)[package],
  preference: () => ref.read(navigationAppProvider),
  presence: ref.read(platformPortsProvider).apps,
);
