import 'package:wendelin_integrations/wendelin_integrations.dart';

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
