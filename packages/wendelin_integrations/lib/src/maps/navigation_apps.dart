import '../location/maps_intents.dart';

/// An app that can navigate (`app` argument of `maps__navigate`).
enum NavigationApp {
  /// Google Maps.
  googleMaps('google_maps', 'Google Maps', googleMapsPackage),

  /// Waze.
  waze('waze', 'Waze', wazePackage);

  const NavigationApp(this.id, this.label, this.package);

  /// Value of the tool argument and of the setting.
  final String id;

  /// Name for texts.
  final String label;

  /// Android package.
  final String package;

  /// The app with the argument value [id], `null` if there is none.
  static NavigationApp? parse(String? id) {
    for (final a in values) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Which navigation apps `maps__navigate` may use. The app implements it
/// over the integration switches, the app detection and the setting
/// „Navigations-App“.
abstract interface class NavigationApps {
  /// The apps whose integration is on and that were found installed at the
  /// last check. Read on every request: the tool offers only these.
  Set<NavigationApp> get active;

  /// The app the user chose in the settings, `null` = default (Google Maps
  /// if active, else Waze).
  NavigationApp? get preferred;

  /// Asks the device right now whether [app] is installed. A failed query
  /// throws a `PortException`.
  Future<bool> isInstalled(NavigationApp app);
}
