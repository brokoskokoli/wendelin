import 'package:wendelin_core/wendelin_core.dart';

import 'calendar_port.dart';
import 'calendar_tools.dart';

/// Device calendar: list, search free time, create, change and delete
/// events in every system calendar (Google, Exchange, CalDAV, local).
final class CalendarIntegration implements Integration {
  /// Creates the integration on [port]. [deviceTimeZone] (IANA name) is
  /// used for confirmation texts; see [CalendarToolEnv].
  CalendarIntegration(CalendarPort port, {String Function()? deviceTimeZone})
    : env = CalendarToolEnv(port, deviceTimeZone: deviceTimeZone);

  /// Id of the permission setup step.
  static const permissionStep = 'calendar_permission';

  /// Shared tool state.
  final CalendarToolEnv env;

  /// Forgets cached event titles and times; call when a session ends.
  void clearCache() => env.clearCache();

  @override
  String get id => 'calendar';

  @override
  String get displayName => 'Kalender';

  @override
  String get iconId => 'calendar';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => true;

  @override
  Future<Availability> checkAvailability() async => Availability.yes;

  @override
  List<SetupStep> get setup => const [
    SetupStep(
      id: permissionStep,
      kind: SetupStepKind.permission,
      label: 'Kalenderzugriff erlauben',
    ),
  ];

  @override
  Future<SetupState> setupState() async => SetupState(
    missingSteps: [if (!await env.port.hasPermission()) permissionStep],
  );

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    ListCalendarsTool(env),
    ListEventsTool(env),
    FindFreeSlotsTool(env),
    CreateEventTool(env),
    UpdateEventTool(env),
    DeleteEventTool(env),
  ]);
}
