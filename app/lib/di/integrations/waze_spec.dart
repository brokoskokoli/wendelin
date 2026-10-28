import 'package:wendelin_integrations/maps.dart';

import '../app_requirements.dart';
import 'integration_spec.dart';

/// Waze over the installed app (no key, no account, WP164 B). It has no
/// tools of its own: it adds the app option to `maps__navigate`, built in
/// `mapsSpec`. Without the app the integration is „nicht verfügbar“.
final wazeSpec = IntegrationSpec(
  id: 'waze',
  isSupported: (d) => d.extra<MapsNavigateTool>('maps') != null,
  requiredApp: KnownApps.waze,
  create: (d) => WazeIntegration(d.extra<MapsNavigateTool>('maps')!),
);
