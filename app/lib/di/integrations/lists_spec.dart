import 'package:wendelin_integrations/lists.dart';

import 'integration_spec.dart';

/// Lists.
final listsSpec = IntegrationSpec(
  id: 'lists',
  // Device: SAF files picked in settings → Listen; demo: in memory.
  isSupported: (d) => d.ports.lists != null,
  create: (d) => ListsIntegration(
    d.ports.lists!.port,
    definitions: d.ports.lists!.definitions,
  ),
);
