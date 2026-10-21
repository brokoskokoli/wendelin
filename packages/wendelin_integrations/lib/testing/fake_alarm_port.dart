import '../src/alarms/alarms.dart';
import '../src/common/port_exception.dart';
import 'fake_failures.dart';

/// A timer set on [FakeAlarmPort].
typedef FakeTimer = ({String id, Duration duration, String? label});

/// In-memory [AlarmPort].
///
/// [returnsIds] `false` behaves like Android intents (no handle, no undo),
/// [canList] `false` makes [listAlarms] return `null`.
final class FakeAlarmPort with FakeFailures implements AlarmPort {
  /// Creates the fake.
  FakeAlarmPort({
    this.returnsIds = true,
    this.canList = true,
    this.available = true,
    this.onlyNext = false,
  });

  /// Returned by [isAvailable].
  bool available;

  /// Whether [setAlarm]/[setTimer] return ids.
  final bool returnsIds;

  /// Whether [listAlarms] is supported.
  final bool canList;

  /// Behaves like Android: [listAlarms] reports only the earliest alarm.
  final bool onlyNext;

  /// Alarms currently set.
  final List<AlarmInfo> alarms = [];

  /// Timers currently running.
  final List<FakeTimer> timers = [];

  int _next = 1;

  @override
  Future<bool> isAvailable() async {
    enter('isAvailable');
    return available;
  }

  @override
  bool get supportsCancel => returnsIds;

  @override
  Future<String?> setAlarm({
    required int hour,
    required int minute,
    String? label,
    Set<int>? days,
  }) async {
    enter('setAlarm');
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
    for (final d in days ?? const <int>{}) {
      RangeError.checkValueInInterval(d, 1, 7, 'days');
    }
    final id = 'a${_next++}';
    alarms.add(
      AlarmInfo(
        id: returnsIds ? id : null,
        hour: hour,
        minute: minute,
        label: label,
        days: days ?? const {},
      ),
    );
    return returnsIds ? id : null;
  }

  @override
  Future<String?> setTimer({required Duration duration, String? label}) async {
    enter('setTimer');
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'muss > 0 sein');
    }
    final id = 't${_next++}';
    timers.add((id: id, duration: duration, label: label));
    return returnsIds ? id : null;
  }

  @override
  Future<void> cancel(String id) async {
    enter('cancel');
    if (!returnsIds) {
      throw const PortException(
        PortErrorKind.unsupported,
        'Wecker können auf diesem Gerät nicht gelöscht werden',
      );
    }
    final before = alarms.length + timers.length;
    alarms.removeWhere((a) => a.id == id);
    timers.removeWhere((t) => t.id == id);
    if (alarms.length + timers.length == before) {
      throw PortException(PortErrorKind.notFound, 'Wecker „$id“ gibt es nicht');
    }
  }

  @override
  Future<List<AlarmInfo>?> listAlarms() async {
    enter('listAlarms');
    if (!canList) return null;
    if (!onlyNext) return List.unmodifiable(alarms);
    final sorted = [...alarms]
      ..sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute));
    return List.unmodifiable(sorted.take(1));
  }

  @override
  bool get listsOnlyNext => onlyNext;
}
