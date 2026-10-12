import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../di/app_settings.dart';
import 'android_alarm_port.dart';
import 'device_calendar_port.dart';
import 'flutter_clipboard_port.dart';
import 'repository_memory_port.dart';

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
  });

  /// Real device ports (Android): calendar channel, system clipboard,
  /// `AlarmClock` intents, memory in the local database.
  factory PlatformPorts.device(WendelinStorage storage) {
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
    );
  }

  /// In-memory ports for the demo mode: nothing touches the device.
  factory PlatformPorts.demo() => PlatformPorts(
    calendar: FakeCalendarPort(),
    clipboard: FakeClipboardPort(),
    alarms: FakeAlarmPort(),
    memory: FakeMemoryStore(),
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
}
