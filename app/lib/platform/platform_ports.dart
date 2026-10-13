import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/app_settings.dart';
import 'android_alarm_port.dart';
import 'device_calendar_port.dart';
import 'flutter_clipboard_port.dart';
import 'repository_memory_port.dart';
import 'saf_list_file_port.dart';

/// The device ports the built-in integrations run on.
///
/// New integrations with device access (e.g. WP12 lists with a
/// `ListFilePort`) add their port here and in [PlatformPorts.device]
/// / [PlatformPorts.demo], then register an `IntegrationSpec`.
final class PlatformPorts {
  /// Creates the bundle.
  const PlatformPorts({
    required this.calendar,
    required this.clipboard,
    required this.alarms,
    required this.memory,
    this.requestCalendarPermission,
    this.lists,
  });

  /// Real device ports (Android): calendar channel, system clipboard,
  /// `AlarmClock` intents, memory in the local database.
  factory PlatformPorts.device(
    WendelinStorage storage, {
    required List<ListDefinition> Function() listDefinitions,
  }) {
    final calendar = DeviceCalendarPort(
      preferredCalendar: () =>
          storage.settings.get(AppSettings.defaultCalendarId),
    );
    return PlatformPorts(
      calendar: calendar,
      clipboard: const FlutterClipboardPort(),
      alarms: const AndroidAlarmPort(),
      memory: RepositoryMemoryPort(storage.memory),
      requestCalendarPermission: calendar.requestPermission,
      lists: ListsPorts(port: SafListFilePort(), definitions: listDefinitions),
    );
  }

  /// In-memory ports for the demo mode: nothing touches the device.
  factory PlatformPorts.demo() => PlatformPorts(
    calendar: FakeCalendarPort(),
    clipboard: FakeClipboardPort(),
    alarms: FakeAlarmPort(),
    memory: FakeMemoryStore(),
    lists: ListsPorts.demo(),
  );

  /// Device calendar.
  final CalendarPort calendar;

  /// System clipboard.
  final ClipboardPort clipboard;

  /// Alarm clock and timers.
  final AlarmPort alarms;

  /// Long-term memory.
  final MemoryStorePort memory;

  /// Asks for calendar access; `null` if the port needs none.
  final Future<bool> Function()? requestCalendarPermission;

  /// List files and definitions; `null` = no lists on this platform.
  final ListsPorts? lists;
}

/// File port and list definitions of the lists integration.
final class ListsPorts {
  /// Creates the bundle.
  const ListsPorts({required this.port, required this.definitions});

  /// In-memory lists „Einkaufen“ and „SmartSSH“ for the demo mode.
  factory ListsPorts.demo() {
    final definitions = [
      ListDefinition(
        id: 'einkaufen',
        name: 'Einkaufen',
        aliases: const ['Einkaufsliste'],
        target: 'demo://Listen/Einkaufen.md',
      ),
      ListDefinition(
        id: 'smartssh',
        name: 'SmartSSH',
        target: 'demo://Projekte/SmartSSH.md',
        section: 'Todo',
      ),
    ];
    return ListsPorts(
      port: FakeListFilePort(
        files: {
          'demo://Listen/Einkaufen.md':
              '# Einkaufen\n\n- [ ] Milch\n- [x] Brot\n',
          'demo://Projekte/SmartSSH.md':
              '# SmartSSH\n\n## Todo\n\n- [ ] Release-Notizen\n',
        },
      ),
      definitions: () => definitions,
    );
  }

  /// Reads and writes the Markdown files.
  final ListFilePort port;

  /// The user's lists.
  final List<ListDefinition> Function() definitions;
}
