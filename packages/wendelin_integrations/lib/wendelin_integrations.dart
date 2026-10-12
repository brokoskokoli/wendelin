/// Built-in Wendelin integrations on top of device ports: calendar,
/// clipboard, alarms, memory and web.
///
/// Device access goes only through the ports ([CalendarPort],
/// [ClipboardPort], [AlarmPort], [MemoryStorePort]); the app implements
/// them. Fakes are in `package:wendelin_integrations/fakes.dart`, contract
/// suites in `package:wendelin_integrations/testing.dart`.
library;

import 'src/alarms/alarms.dart';
import 'src/calendar/calendar_port.dart';
import 'src/clipboard/clipboard.dart';
import 'src/memory/memory.dart';

export 'src/alarms/alarms.dart';
export 'src/calendar/calendar_integration.dart';
export 'src/calendar/calendar_port.dart';
export 'src/calendar/calendar_tools.dart';
export 'src/calendar/free_slots.dart';
export 'src/clipboard/clipboard.dart';
export 'src/common/base_tool.dart' show IntegrationTool;
export 'src/common/port_exception.dart';
export 'src/common/time.dart' show LocalDate, timeZoneLocation;
export 'src/common/tool_args.dart' show InvalidArgumentsException, ToolArgs;
export 'src/memory/memory.dart';
export 'src/memory/sensitive_content.dart';
export 'src/web/fetch_guard.dart';
export 'src/web/web_fetcher.dart';
export 'src/web/web_integration.dart';
export 'src/web/web_search_backend.dart'
    show
        BraveSearchBackend,
        SearxngBackend,
        TavilyBackend,
        WebSearchBackend,
        WebSearchResult;
