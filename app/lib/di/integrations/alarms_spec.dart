import 'package:wendelin_integrations/alarm.dart';

import 'integration_spec.dart';

/// Alarms and timers.
final alarmsSpec = IntegrationSpec(
  id: 'alarms',
  create: (d) => AlarmsIntegration(d.ports.alarms),
);
