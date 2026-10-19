/// A position fix. Coordinates are personal data: keep them out of logs,
/// the audit log and error texts.
final class GeoFix {
  /// Creates a fix.
  const GeoFix({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.placeName,
  });

  /// Latitude in degrees (−90 … 90).
  final double latitude;

  /// Longitude in degrees (−180 … 180).
  final double longitude;

  /// Estimated horizontal accuracy in metres, if the provider tells it.
  final double? accuracyMeters;

  /// Name of the place (e.g. „Altstadt, Hamburg“) if the device geocoder is
  /// available and found one.
  final String? placeName;
}

/// The device position, read once on request (no background location, no
/// Google Play services, no API key).
///
/// Android: `LocationManager` (GPS, network, passive); the place name comes
/// from `android.location.Geocoder` if the device has a backend. Failures
/// throw `PortException` with a short German text: permission missing
/// (`permissionDenied`), location switched off or no fix in time
/// (`unavailable`). Must never put coordinates into an exception message.
abstract interface class LocationPort {
  /// Whether the user granted the (fine or coarse) location permission.
  Future<bool> hasPermission();

  /// Asks the user for the location permission (foreground only); returns
  /// whether it is granted afterwards.
  Future<bool> requestPermission();

  /// The current position, named if possible.
  Future<GeoFix> current();
}

/// An `ACTION_VIEW` intent for a map app: [uri] and, if the intent must go
/// to one app, its [package].
final class MapsLaunch {
  /// Creates a launch.
  const MapsLaunch(this.uri, {this.package});

  /// The data URI (`google.navigation:`, `https://www.google.com/maps/…`,
  /// `geo:`).
  final Uri uri;

  /// Android package that has to handle the intent, `null` = any app.
  final String? package;

  @override
  String toString() => 'MapsLaunch(${package ?? 'any'})';
}

/// Starts map apps. Throws `PortException(notFound)` if no app handles the
/// intent.
abstract interface class MapsLauncherPort {
  /// Starts [launch] as a new task.
  Future<void> launch(MapsLaunch launch);
}
