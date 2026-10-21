import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../common/base_tool.dart';
import '../common/port_exception.dart';
import '../common/time.dart';
import '../common/tool_args.dart';

/// Alarm clock and timers (Android `AlarmClock` intents, iOS AlarmKit or
/// notifications). Must pass `alarmPortContract`.
///
/// Android intents give no handle back: [setAlarm]/[setTimer] then return
/// `null`, and nothing can be undone or listed.
abstract interface class AlarmPort {
  /// Whether alarms and timers can be set on this device at all (a clock
  /// app handles the intent, or the notification fallback is available,
  /// K7).
  Future<bool> isAvailable();

  /// Whether alarms and timers set by this port can be cancelled again
  /// ([setAlarm]/[setTimer] then always return ids). `false` for Android
  /// `AlarmClock` intents.
  bool get supportsCancel;

  /// Sets an alarm at [hour]:[minute] (device time), repeating on [days]
  /// (ISO weekdays 1 = Monday … 7 = Sunday) or once if `null`/empty.
  /// Returns an id if the alarm can be cancelled later, else `null`.
  /// Throws [ArgumentError] for out-of-range values.
  Future<String?> setAlarm({
    required int hour,
    required int minute,
    String? label,
    Set<int>? days,
  });

  /// Starts a timer of [duration] (> 0). Returns an id if it can be
  /// cancelled later, else `null`. Throws [ArgumentError] for non-positive
  /// durations.
  Future<String?> setTimer({required Duration duration, String? label});

  /// Cancels the alarm or timer [id] returned by [setAlarm]/[setTimer].
  /// Throws `PortException(notFound)` for unknown ids and
  /// `PortException(unsupported)` if [supportsCancel] is `false`.
  Future<void> cancel(String id);

  /// The alarms set on the device, or `null` if the platform cannot list
  /// them. With [listsOnlyNext] the list holds at most the next alarm
  /// (empty = no alarm set).
  Future<List<AlarmInfo>?> listAlarms();

  /// Whether [listAlarms] knows only the next alarm of the device, not all
  /// of them (Android: `AlarmManager.getNextAlarmClock`, WP119).
  bool get listsOnlyNext;
}

/// An alarm reported by [AlarmPort.listAlarms].
@immutable
final class AlarmInfo {
  /// Creates alarm info; [days] is copied unmodifiable.
  AlarmInfo({
    required this.hour,
    required this.minute,
    this.id,
    this.label,
    Set<int> days = const {},
    this.enabled = true,
    this.at,
  }) : days = Set.unmodifiable(days);

  /// Id, if the platform has one.
  final String? id;

  /// Hour 0–23.
  final int hour;

  /// Minute 0–59.
  final int minute;

  /// Label, if any.
  final String? label;

  /// Repeat days (ISO weekdays); empty = once.
  final Set<int> days;

  /// Whether the alarm is active.
  final bool enabled;

  /// The next time it rings, if the platform knows it.
  final DateTime? at;

  @override
  bool operator ==(Object other) =>
      other is AlarmInfo &&
      other.id == id &&
      other.hour == hour &&
      other.minute == minute &&
      other.label == label &&
      const SetEquality<int>().equals(other.days, days) &&
      other.enabled == enabled &&
      other.at == at;

  @override
  int get hashCode => Object.hash(
    id,
    hour,
    minute,
    label,
    const SetEquality<int>().hash(days),
    enabled,
    at,
  );

  @override
  String toString() => 'AlarmInfo(${_clock(hour, minute)}, $label, $days)';
}

String _clock(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

const _dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

/// German day list, e.g. `Mo–Fr`, `Sa, So`, `einmalig`.
String germanDays(Set<int> days) {
  if (days.isEmpty) return 'einmalig';
  final sorted = days.toList()..sort();
  if (sorted.length == 7) return 'täglich';
  if (const ListEquality<int>().equals(sorted, [1, 2, 3, 4, 5])) {
    return 'Mo–Fr';
  }
  return sorted.map((d) => _dayNames[d - 1]).join(', ');
}

/// German duration, e.g. `10 min`, `1 h 30 min`, `45 s`.
String germanDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return [
    if (h > 0) '$h h',
    if (m > 0) '$m min',
    if (s > 0 || d == Duration.zero) '$s s',
  ].join(' ');
}

/// Alarms and timers: `alarms__set_alarm`, `alarms__set_timer`,
/// `alarms__list`.
final class AlarmsIntegration implements Integration {
  /// Creates the integration on [port].
  AlarmsIntegration(this.port);

  /// Device alarm clock.
  final AlarmPort port;

  @override
  String get id => 'alarms';

  @override
  String get displayName => 'Wecker und Timer';

  @override
  String get iconId => 'alarm';

  @override
  Set<AppPlatform> get platforms => const {
    AppPlatform.android,
    AppPlatform.ios,
  };

  @override
  bool get sensitive => false;

  @override
  Future<Availability> checkAvailability() async => await port.isAvailable()
      ? Availability.yes
      : const Availability(
          available: false,
          reason: 'Auf diesem Gerät können keine Wecker gestellt werden.',
        );

  @override
  List<SetupStep> get setup => const [];

  @override
  Future<SetupState> setupState() async => SetupState();

  @override
  late final List<Tool> tools = List.unmodifiable(<Tool>[
    SetAlarmTool(port),
    SetTimerTool(port),
    ListAlarmsTool(port),
  ]);
}

/// `alarms__set_alarm` (write; undo only if the platform returns an id).
final class SetAlarmTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool.
  const SetAlarmTool(this.port);

  /// Device alarm clock.
  final AlarmPort port;

  @override
  String get name => 'alarms__set_alarm';

  @override
  String get description =>
      'Set an alarm clock at a time of day. Example: time "07:30", days '
      '[1,2,3,4,5] for Monday to Friday. Without days it rings once.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'time': {
        'type': 'string',
        'description': 'Time of day as HH:MM, e.g. "06:45".',
      },
      'label': {'type': 'string', 'description': 'Name, e.g. "Tauchen".'},
      'days': {
        'type': 'array',
        'items': {'type': 'integer', 'minimum': 1, 'maximum': 7},
        'description': 'Repeat on these days, 1=Monday … 7=Sunday.',
      },
    },
    'required': ['time'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  ({int hour, int minute, String? label, Set<int> days}) _read(ToolArgs args) {
    final minutes = parseClockTime(args.requireString('time'), 'time');
    if (minutes >= 24 * 60) {
      throw const InvalidArgumentsException('„time“ muss vor 24:00 liegen');
    }
    final label = args.optString('label');
    return (
      hour: minutes ~/ 60,
      minute: minutes % 60,
      label: label == null || label.isEmpty ? null : label,
      days: args.optIntList('days', min: 1, max: 7)?.toSet() ?? const {},
    );
  }

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final a = _read(args);
    final id = await port.setAlarm(
      hour: a.hour,
      minute: a.minute,
      label: a.label,
      days: a.days.isEmpty ? null : a.days,
    );
    final when = '${_clock(a.hour, a.minute)} (${germanDays(a.days)})';
    return ToolOutcome.text(
      'Wecker gestellt: $when${a.label == null ? '' : ', „${a.label}“'}.',
      summary: 'Wecker gestellt: $when',
      undo: id == null
          ? null
          : UndoAction(label: 'Wecker löschen', run: () => port.cancel(id)),
    );
  }

  @override
  String describe(ToolArgs args) {
    final a = _read(args);
    return 'Wecker ${_clock(a.hour, a.minute)} (${germanDays(a.days)}) stellen';
  }

  @override
  String get fallbackDescription => 'Wecker stellen';
}

/// `alarms__set_timer` (write; undo only if the platform returns an id).
final class SetTimerTool extends IntegrationTool
    implements TrustedContentSource {
  /// Creates the tool.
  const SetTimerTool(this.port);

  /// Device alarm clock.
  final AlarmPort port;

  /// Longest timer (24 h).
  static const maxSeconds = 24 * 3600;

  @override
  String get name => 'alarms__set_timer';

  @override
  String get description =>
      'Start a countdown timer. duration_seconds: e.g. 600 for 10 minutes, '
      '90 for one and a half minutes.';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': {
      'duration_seconds': {
        'type': 'integer',
        'minimum': 1,
        'maximum': maxSeconds,
        'description': 'Length in seconds.',
      },
      'label': {'type': 'string', 'description': 'Name, e.g. "Nudeln".'},
    },
    'required': ['duration_seconds'],
  };

  @override
  RiskLevel get risk => RiskLevel.write;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final duration = Duration(
      seconds: args.requireInt('duration_seconds', min: 1, max: maxSeconds),
    );
    final rawLabel = args.optString('label');
    final label = rawLabel == null || rawLabel.isEmpty ? null : rawLabel;
    final id = await port.setTimer(duration: duration, label: label);
    final ends = ctx.clock.now().add(duration);
    final text = germanDuration(duration);
    return ToolOutcome.text(
      'Timer gestellt: $text${label == null ? '' : ', „$label“'}; '
      'läuft ab um ${isoInZone(ends, timeZoneLocation(ctx.timeZone))}.',
      summary: 'Timer: $text',
      undo: id == null
          ? null
          : UndoAction(label: 'Timer löschen', run: () => port.cancel(id)),
    );
  }

  @override
  String describe(ToolArgs args) =>
      'Timer ${germanDuration(Duration(seconds: args.requireInt('duration_seconds', min: 1, max: maxSeconds)))} stellen';

  @override
  String get fallbackDescription => 'Timer stellen';
}

/// `alarms__list` (read; not supported on every platform).
final class ListAlarmsTool extends IntegrationTool {
  /// Creates the tool.
  const ListAlarmsTool(this.port);

  /// Device alarm clock.
  final AlarmPort port;

  @override
  String get name => 'alarms__list';

  @override
  String get description =>
      'List the alarms set on the device (not possible on every device; '
      'Android knows only the next alarm: then "only_next" is true and an '
      'empty list means no alarm is set).';

  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'properties': <String, Object?>{},
    'required': <String>[],
  };

  @override
  RiskLevel get risk => RiskLevel.read;

  @override
  Future<ToolOutcome> run(ToolArgs args, ToolContext ctx) async {
    final alarms = await port.listAlarms();
    if (alarms == null) {
      throw const PortException(
        PortErrorKind.unsupported,
        'Auf diesem Gerät können Wecker nicht ausgelesen werden.',
      );
    }
    final sorted = [...alarms]
      ..sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
    final zone = timeZoneLocation(ctx.timeZone);
    final onlyNext = port.listsOnlyNext;
    return jsonOutcome({
      'alarms': [
        for (final a in sorted)
          {
            'time': _clock(a.hour, a.minute),
            if (a.at != null) 'next_ring': isoInZone(a.at!, zone),
            if (a.label != null) 'label': a.label,
            'days': germanDays(a.days),
            if (!a.enabled) 'enabled': false,
          },
      ],
      if (onlyNext) 'only_next': true,
      if (onlyNext)
        'note': alarms.isEmpty
            ? 'Es ist kein Wecker gestellt.'
            : 'Nur der nächste Wecker ist bekannt, weitere kann Android '
                  'nicht auslesen.',
    }, summary: onlyNext ? _nextSummary(alarms) : '${alarms.length} Wecker');
  }

  static String _nextSummary(List<AlarmInfo> alarms) => alarms.isEmpty
      ? 'Kein Wecker gestellt'
      : 'Nächster Wecker ${_clock(alarms.first.hour, alarms.first.minute)}';

  @override
  String describe(ToolArgs args) => 'Wecker auflisten';

  @override
  String get fallbackDescription => 'Wecker auflisten';
}
