import 'dart:math' as math;

import 'location_port.dart';

/// Android package of Google Maps.
const googleMapsPackage = 'com.google.android.apps.maps';

/// Android package of Waze.
const wazePackage = 'com.waze';

/// How to get to a destination.
enum TravelMode {
  /// By car.
  driving('d', 'driving'),

  /// On foot.
  walking('w', 'walking'),

  /// By bike.
  bicycling('b', 'bicycling'),

  /// Public transport (Google Maps only through its directions page).
  transit(null, 'transit');

  const TravelMode(this.navCode, this.webName);

  /// `mode=` of `google.navigation:`, `null` if that scheme has none.
  final String? navCode;

  /// `travelmode=` of the Google Maps URL and the tool argument value.
  final String webName;

  /// The mode named [name] (the tool argument); `null` for an unknown one.
  static TravelMode? parse(String name) {
    for (final m in values) {
      if (m.webName == name) return m;
    }
    return null;
  }
}

/// Builds the map intents. Pure, so the URIs are unit-tested; the platform
/// only starts them.
abstract final class MapsIntents {
  /// Navigation to [destination] (address, place name or „lat,lon“).
  ///
  /// With [googleMaps] the intent goes to Google Maps (turn-by-turn for car,
  /// foot and bike, the route page for transit); otherwise a `geo:` query
  /// that every map app (Organic Maps, OsmAnd, …) shows, without starting
  /// guidance.
  static MapsLaunch navigate(
    String destination, {
    TravelMode mode = TravelMode.driving,
    required bool googleMaps,
  }) {
    final q = Uri.encodeComponent(destination);
    if (!googleMaps) return _geoQuery(q);
    final code = mode.navCode;
    if (code != null) {
      return MapsLaunch(
        Uri.parse('google.navigation:q=$q&mode=$code'),
        package: googleMapsPackage,
      );
    }
    return MapsLaunch(
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$q'
        '&travelmode=${mode.webName}',
      ),
      package: googleMapsPackage,
    );
  }

  /// Navigation to [destination] in Waze: `https://waze.com/ul?q=…&navigate=yes`
  /// (Waze knows no mode: it always guides by car). Only Waze may handle it.
  static MapsLaunch navigateWaze(String destination) => MapsLaunch(
    Uri.parse(
      'https://waze.com/ul?q=${Uri.encodeComponent(destination)}&navigate=yes',
    ),
    package: wazePackage,
  );

  /// Search for [query] on the map (place, category, address).
  static MapsLaunch search(String query, {required bool googleMaps}) {
    final q = Uri.encodeComponent(query);
    if (!googleMaps) return _geoQuery(q);
    return MapsLaunch(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
      package: googleMapsPackage,
    );
  }

  static MapsLaunch _geoQuery(String encoded) =>
      MapsLaunch(Uri.parse('geo:0,0?q=$encoded'));
}

/// Great-circle distance in metres between two points (Haversine, mean
/// earth radius): the straight line, not the route.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const radius = 6371008.8;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * radius * math.asin(math.min(1, math.sqrt(a)));
}

/// „ca. 450 m“, „ca. 3,4 km“, „ca. 120 km“ for [meters] (German decimal
/// comma; rounded on purpose, it is a straight line).
String formatDistance(double meters) {
  if (meters < 1000) {
    final rounded = (meters / 10).round() * 10;
    return rounded == 0 ? 'unter 10 m' : 'ca. $rounded m';
  }
  final km = meters / 1000;
  if (km < 10) return 'ca. ${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  return 'ca. ${km.round()} km';
}

/// [value] rounded to three decimals (about 100 m) as text.
String roundedCoordinate(double value) => value.toStringAsFixed(3);
