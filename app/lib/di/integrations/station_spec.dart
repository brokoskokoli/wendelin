import 'package:wendelin_integrations/station.dart';

import 'integration_spec.dart';

/// Station mode (WP99): only the start by voice. Not allowed while locked
/// (K63: the voice command works on an unlocked device only).
final stationSpec = IntegrationSpec(
  id: 'station',
  isSupported: (d) => d.ports.station != null,
  create: (d) => StationIntegration(d.ports.station!),
);
