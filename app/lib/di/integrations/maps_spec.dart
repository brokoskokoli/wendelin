import 'package:wendelin_integrations/maps.dart';

import '../app_requirements.dart';
import '../navigation_apps.dart';
import '../providers.dart';
import 'integration_spec.dart';

/// Google Maps adapter over the installed app (no API key, no permission).
/// Without the app the integration is „nicht verfügbar“ and its tools
/// stay out of the catalog.
///
/// `prepare` builds `maps__navigate` once: the `waze` integration offers
/// the same instance (WP164 B), so the tool is there while either is on.
final mapsSpec = IntegrationSpec(
  id: 'maps',
  prepare: (ref) {
    final ports = ref.watch(platformPortsProvider);
    final launcher = ports.mapsLauncher;
    if (launcher == null) return null;
    return MapsNavigateTool(launcher, appNavigationApps(ref));
  },
  isSupported: (d) => d.extra<MapsNavigateTool>('maps') != null,
  requiredApp: KnownApps.googleMaps,
  create: (d) => MapsIntegration(
    d.ports.mapsLauncher!,
    d.extra<MapsNavigateTool>('maps')!,
  ),
);
