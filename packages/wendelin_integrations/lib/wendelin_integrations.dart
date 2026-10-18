/// Built-in Wendelin integrations on top of device ports: calendar,
/// clipboard, alarms, memory, web, weather, lists, Obsidian and Bring!, plus
/// user-defined HTTP tools (`HttpToolsIntegration`).
///
/// Device access goes only through the ports (`CalendarPort`,
/// `ClipboardPort`, `AlarmPort`, `MemoryStorePort`, `ListFilePort`,
/// `VaultPort`, `NoteIndexPort`, `AppPresencePort`, and for Bring!
/// `BringApi` and `BringSecrets`); the app implements them.
/// Fakes are in `package:wendelin_integrations/fakes.dart`, contract
/// suites in `package:wendelin_integrations/testing.dart`.
///
/// One export line per integration entry point (alphabetical); a new
/// integration adds exactly one line here.
library;

export 'alarm.dart';
export 'apps.dart';
export 'bring.dart';
export 'calendar.dart';
export 'clipboard.dart';
export 'common.dart';
export 'flashlight.dart';
export 'home_assistant.dart';
export 'http_tools.dart';
export 'lists.dart';
export 'memory.dart';
export 'obsidian.dart';
export 'user.dart';
export 'weather.dart';
export 'web.dart';
