import 'package:wendelin_core/wendelin_core.dart';

import '../common/app_presence.dart';
import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/tool_args.dart';
import '../weather/weather_model.dart';
import '../weather/weather_service.dart';
import 'location_port.dart';
import 'maps_intents.dart';

const _noMapApp =
    'Keine Karten-App gefunden. Installiere Google Maps, Organic Maps '
    'oder OsmAnd.';

/// Whether Google Maps is installed; an unreadable answer counts as no.
Future<bool> hasGoogleMaps(AppPresencePort apps) async {
  try {
    return await apps.isInstalled(googleMapsPackage);
  } on PortException {
    return false;
  }
}

/// Starts [primary] (Google Maps) if [useGoogle], and falls back to
/// [fallback] (`geo:`) if that app does not take it or is not installed.
/// Throws `PortException(notFound)` with [_noMapApp] if no app is left.
Future<void> launchWithFallback(
  MapsLauncherPort launcher, {
  required bool useGoogle,
  required MapsLaunch Function(bool googleMaps) build,
}) async {
  if (useGoogle) {
    try {
      await launcher.launch(build(true));
      return;
    } on PortException catch (e) {
      if (e.kind != PortErrorKind.notFound) rethrow;
    }
  }
  try {
    await launcher.launch(build(false));
  } on PortException catch (e) {
    if (e.kind != PortErrorKind.notFound) rethrow;
    throw const PortException(PortErrorKind.notFound, _noMapApp);
  }
}

/// The `destination` argument shared by the navigation tools.
const destinationProperty = <String, Object?>{
  'type': 'string',
  'description':
      'Destination: address, place name or "latitude,longitude". Use what '
      'the user said; do not make up an address.',
  'maxLength': 200,
};

/// The optional `mode` argument of the navigation tools.
const modeProperty = <String, Object?>{
  'type': 'string',
  'enum': ['driving', 'walking', 'bicycling', 'transit'],
  'description': 'Travel mode, default driving.',
};

/// Reads `destination` (required, trimmed) from [args].
String requireDestination(ToolArgs args) {
  final d = args.requireString('destination').trim();
  if (d.isEmpty) throw const InvalidArgumentsException('„destination“ fehlt');
  if (d.length > 200) {
    throw const InvalidArgumentsException('„destination“ ist zu lang');
  }
  return d;
}

/// Reads `mode` from [args] (default driving).
TravelMode readMode(ToolArgs args) {
  final raw = args.optString('mode');
  if (raw == null) return TravelMode.driving;
  return TravelMode.parse(raw) ??
      (throw const InvalidArgumentsException(
        '„mode“ muss driving, walking, bicycling oder transit sein',
      ));
}

/// `location__current` (read): where the user is, as a place name if the
/// device knows one, else with rounded coordinates.
final class LocationCurrentTool extends IntegrationTool {
  /// Creates the tool.
  const LocationCurrentTool(this.port);

  /// The device position.
  final LocationPort port;

  @override
  String get name => 'location__current';

  @override
  String get description =>
      'Tell where the user is right now (place name, else rounded '
      'coordinates). Use it for "where am I" and for questions that need '
      'the current location.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final fix = await port.current();
    final place = fix.placeName?.trim();
    final accuracy = fix.accuracyMeters;
    final data = <String, Object?>{
      if (place != null && place.isNotEmpty)
        'place': place
      else ...{
        'latitude': roundedCoordinate(fix.latitude),
        'longitude': roundedCoordinate(fix.longitude),
        'note': 'Koordinaten auf etwa 100 m gerundet',
      },
      if (accuracy != null) 'accuracy_m': (accuracy / 10).round() * 10,
    };
    // The summary stays free of place and coordinates (chat history).
    return jsonOutcome(data, summary: 'Standort ermittelt');
  }

  @override
  String describe(ToolArgs args) => 'Aktuellen Standort bestimmen';

  @override
  String get fallbackDescription => 'Aktuellen Standort bestimmen';
}

/// `location__navigate_to` (write): starts navigation in Google Maps if it
/// is installed, else in any map app through a `geo:` intent.
final class LocationNavigateToTool extends IntegrationTool {
  /// Creates the tool.
  const LocationNavigateToTool(this.launcher, this.apps);

  /// Starts map apps.
  final MapsLauncherPort launcher;

  /// Installed-app check (Google Maps).
  final AppPresencePort apps;

  @override
  String get name => 'location__navigate_to';

  @override
  String get description =>
      'Start navigation to a destination in the map app (Google Maps if '
      'installed, otherwise any map app such as Organic Maps or OsmAnd). '
      'Without Google Maps the app only shows the destination.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'destination': destinationProperty,
      'mode': modeProperty,
    },
    'required': <String>['destination'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final destination = requireDestination(args);
    final mode = readMode(args);
    final google = await hasGoogleMaps(apps);
    await launchWithFallback(
      launcher,
      useGoogle: google,
      build: (g) =>
          MapsIntents.navigate(destination, mode: mode, googleMaps: g),
    );
    return ToolOutcome.text(
      'Die Karten-App ist geöffnet.',
      summary: 'Navigation gestartet',
    );
  }

  // The audit log stores confirmation texts: no destination in it.
  @override
  String describe(ToolArgs args) => 'Navigation starten';

  @override
  String get fallbackDescription => 'Navigation starten';
}

/// `location__distance_to` (read): straight-line distance from the current
/// position to a place name or to coordinates.
final class LocationDistanceToTool extends IntegrationTool {
  /// Creates the tool; without [geocoder] only coordinates work.
  const LocationDistanceToTool(this.port, this.geocoder);

  /// The device position.
  final LocationPort port;

  /// Place search for names (the name goes to the geocoding service, never
  /// the user's position).
  final Geocoder? geocoder;

  @override
  String get name => 'location__distance_to';

  @override
  String get description =>
      'Tell the approximate straight-line distance (as the crow flies, not '
      'the driving distance) from the user\'s current position to a place '
      'name or to coordinates.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{
      'destination': {
        'type': 'string',
        'description':
            'Place name, address or "latitude,longitude" (e.g. "53.55,9.99").',
        'maxLength': 200,
      },
    },
    'required': <String>['destination'],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  static final _coordinates = RegExp(
    r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)\s*$',
  );

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final name = requireDestination(args);
    final coords = _coordinates.firstMatch(name);
    final lat = coords == null ? null : double.parse(coords[1]!);
    final lon = coords == null ? null : double.parse(coords[2]!);
    if (lat != null && (lat.abs() > 90 || lon!.abs() > 180)) {
      throw const InvalidArgumentsException(
        'Koordinaten außerhalb des Bereichs',
      );
    }
    var targetLat = lat;
    var targetLon = lon;
    var label = name;
    if (targetLat == null) {
      final g = geocoder;
      if (g == null) {
        throw const PortException(
          PortErrorKind.unsupported,
          'Ortsnamen lassen sich hier nicht nachschlagen, nenne "Breite,Länge".',
        );
      }
      final language = ctx.locale.split(RegExp('[-_]')).first;
      final Place? place;
      try {
        place = await g.find(name, language: language, cancel: ctx.cancel);
      } on CancelledException {
        rethrow;
      } on Exception {
        throw const PortException(
          PortErrorKind.unavailable,
          'Die Ortssuche ist gerade nicht erreichbar.',
        );
      }
      if (place == null) {
        throw PortException(
          PortErrorKind.notFound,
          'Den Ort „${ellipsize(name, 60)}“ habe ich nicht gefunden.',
        );
      }
      targetLat = place.latitude;
      targetLon = place.longitude;
      label = place.name;
    }
    final fix = await port.current();
    final meters = haversineMeters(
      fix.latitude,
      fix.longitude,
      targetLat,
      targetLon!,
    );
    final text = formatDistance(meters);
    final data = <String, Object?>{
      'distance': text,
      'distance_m': (meters / 10).round() * 10,
      'kind': 'Luftlinie, nicht die Fahrstrecke',
      if (coords == null && label.isNotEmpty) 'to': ellipsize(label, 80),
    };
    return jsonOutcome(data, summary: 'Entfernung berechnet');
  }

  @override
  String describe(ToolArgs args) => 'Entfernung zum Ziel berechnen';

  @override
  String get fallbackDescription => 'Entfernung zum Ziel berechnen';
}
