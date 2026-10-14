import 'package:wendelin_integrations/memory.dart';

import 'integration_spec.dart';

/// Memory.
final memorySpec = IntegrationSpec(
  id: 'memory',
  create: (d) => MemoryIntegration(d.ports.memory),
);
