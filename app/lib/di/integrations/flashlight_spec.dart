import 'package:wendelin_integrations/flashlight.dart';

import 'integration_spec.dart';

/// Flashlight. Allowed on a locked device (used by WP53).
final flashlightSpec = IntegrationSpec(
  id: 'flashlight',
  create: (d) => FlashlightIntegration(d.ports.torch),
  allowedWhileLocked: true,
);
