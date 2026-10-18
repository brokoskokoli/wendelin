import 'package:wendelin_integrations/lists.dart';

import 'integration_spec.dart';

/// Tasks (due dates and priorities on the lists).
final tasksSpec = IntegrationSpec(
  id: 'tasks',
  // Same files and definitions as the lists.
  isSupported: (d) => d.ports.lists != null,
  create: (d) => TasksIntegration(
    d.ports.lists!.port,
    definitions: d.ports.lists!.definitions,
  ),
);
