import 'package:wendelin_integrations/maps.dart';

import '../app_requirements.dart';
import 'integration_spec.dart';

/// Google Maps adapter over the installed app (no API key, no permission).
/// Without the app the integration is „nicht verfügbar“ and its tools
/// stay out of the catalog.
final mapsSpec = IntegrationSpec(
  id: 'maps',
  isSupported: (d) => d.ports.mapsLauncher != null,
  requiredApp: KnownApps.googleMaps,
  create: (d) => MapsIntegration(d.ports.mapsLauncher!),
);
