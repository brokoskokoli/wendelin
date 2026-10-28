import '../common/tool_args.dart';
import '../location/location_port.dart';
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

/// Why no navigation app could be used ([NavigationStarter.resolve]).
typedef NavigationUnavailable = ({String message, String summary});

/// Picks the navigation app and starts it: the one path of `maps__navigate`
/// and `contacts__navigate` (WP164 C), so both obey the same rules. Fail
/// closed: the chosen app or nothing, never the other one.
final class NavigationStarter {
  /// Creates the starter.
  const NavigationStarter(this.launcher, this.apps);

  /// Starts map apps.
  final MapsLauncherPort launcher;

  /// The usable navigation apps and the user's choice.
  final NavigationApps apps;

  /// The app for [requested] (`app` argument, `null` = setting, else Google
  /// Maps if active, else Waze) or the reason there is none. Throws
  /// [InvalidArgumentsException] for an unknown app id.
  Future<({NavigationApp? app, NavigationUnavailable? unavailable})> resolve(
    String? requested, {
    TravelMode mode = TravelMode.driving,
  }) async {
    final NavigationApp? chosen;
    if (requested != null) {
      chosen =
          NavigationApp.parse(requested) ??
          (throw const InvalidArgumentsException(
            '„app“ muss google_maps oder waze sein',
          ));
    } else {
      final active = apps.active;
      chosen =
          apps.preferred ??
          (active.contains(NavigationApp.googleMaps)
              ? NavigationApp.googleMaps
              : active.contains(NavigationApp.waze)
              ? NavigationApp.waze
              : null);
    }
    if (chosen == null || !apps.active.contains(chosen)) {
      return (
        app: null,
        unavailable: (
          message:
              '${chosen?.label ?? 'Keine Navigations-App'} ist nicht '
              'eingerichtet oder nicht installiert.',
          summary: 'Navigations-App nicht verfügbar',
        ),
      );
    }
    if (!await apps.isInstalled(chosen)) {
      return (
        app: null,
        unavailable: (
          message: '${chosen.label} ist nicht installiert.',
          summary: 'Navigations-App nicht verfügbar',
        ),
      );
    }
    if (chosen == NavigationApp.waze && mode != TravelMode.driving) {
      return (
        app: null,
        unavailable: (
          message:
              'Waze navigiert nur mit dem Auto; für diese Fortbewegungsart '
              'eine andere App wählen.',
          summary: 'Waze: nur Auto',
        ),
      );
    }
    return (app: chosen, unavailable: null);
  }

  /// Starts navigation to [destination] in [app] (from [resolve]).
  Future<void> launch(
    NavigationApp app,
    String destination, {
    TravelMode mode = TravelMode.driving,
  }) => launcher.launch(switch (app) {
    NavigationApp.waze => MapsIntents.navigateWaze(destination),
    NavigationApp.googleMaps => MapsIntents.navigate(
      destination,
      mode: mode,
      googleMaps: true,
    ),
  });
}
