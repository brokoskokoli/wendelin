import 'package:wendelin_integrations/location.dart';
import 'package:wendelin_integrations/weather.dart' show Geocoder;

import '../app_requirements.dart';
import '../weather.dart';
import 'integration_spec.dart';

/// Location and navigation over `LocationManager` and map intents. Switching
/// it on asks for the location permission (foreground only; the explanation
/// is translated: `integrationsLocationRationale`). Google Maps is optional:
/// without it navigation falls back to a `geo:` intent. Place names for
/// distances come from the weather geocoder (the name goes out, never the
/// position).
final locationSpec = IntegrationSpec(
  id: 'location',
  prepare: (ref) => ref.watch(weatherGeocoderProvider),
  isSupported: (d) => d.ports.location != null && d.ports.mapsLauncher != null,
  requiredApp: KnownApps.googleMaps.optional(
    'Google Maps fehlt: Navigation mit anderer Karten-App',
  ),
  create: (d) => LocationIntegration(
    d.ports.location!,
    d.ports.mapsLauncher!,
    d.ports.apps,
    geocoder: d.extra<Geocoder>('location'),
  ),
  requestPermission: (d) => d.ports.location!.requestPermission(),
);
