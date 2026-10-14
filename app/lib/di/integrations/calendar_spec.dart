import 'package:wendelin_integrations/calendar.dart';

import 'integration_spec.dart';

/// Calendar: needs the OS calendar permission when switched on.
final calendarSpec = IntegrationSpec(
  id: 'calendar',
  create: (d) => CalendarIntegration(
    d.ports.calendar,
    deviceTimeZone: () => d.device.timeZone,
  ),
  requestPermission: (d) async =>
      await d.ports.requestCalendarPermission?.call() ?? true,
  permissionRationale:
      'Wendelin braucht Zugriff auf deine Kalender, um Termine zu lesen, '
      'anzulegen und zu ändern. Android fragt dich gleich danach. Löschen '
      'fragt Wendelin immer vorher nach.',
);
