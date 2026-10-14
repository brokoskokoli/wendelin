/// Calendar integration: `CalendarPort`, read and write tools, free slots.
///
/// Entry point of one integration; `wendelin_integrations.dart` re-exports it.
library;

export 'src/calendar/calendar_integration.dart';
export 'src/calendar/calendar_port.dart';
export 'src/calendar/calendar_read_tools.dart';
export 'src/calendar/calendar_tools.dart'
    show CalendarToolEnv, describeEventSpan;
export 'src/calendar/calendar_write_tools.dart';
export 'src/calendar/free_slots.dart';
