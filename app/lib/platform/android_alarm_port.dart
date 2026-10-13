import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';
import 'package:platform/platform.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// [AlarmPort] over the Android `AlarmClock` intents
/// (`ACTION_SET_ALARM`/`ACTION_SET_TIMER` with `EXTRA_SKIP_UI`).
///
/// The intents return no handle: nothing can be cancelled or listed
/// ([supportsCancel] is `false`, [listAlarms] returns `null`). Whether a
/// clock app handles them is checked by intent resolution (the manifest
/// declares both actions in `<queries>`). Without a clock app the
/// integration is unavailable; the notification fallback from K7 is still
/// open.
final class AndroidAlarmPort implements AlarmPort {
  /// Creates the port; `platform` is injectable for tests (default: the
  /// real platform).
  const AndroidAlarmPort({this._platform});

  final Platform? _platform;

  /// `AlarmClock.ACTION_SET_ALARM`.
  static const actionSetAlarm = 'android.intent.action.SET_ALARM';

  /// `AlarmClock.ACTION_SET_TIMER`.
  static const actionSetTimer = 'android.intent.action.SET_TIMER';

  /// `AlarmClock.EXTRA_HOUR`.
  static const extraHour = 'android.intent.extra.alarm.HOUR';

  /// `AlarmClock.EXTRA_MINUTES`.
  static const extraMinutes = 'android.intent.extra.alarm.MINUTES';

  /// `AlarmClock.EXTRA_MESSAGE`.
  static const extraMessage = 'android.intent.extra.alarm.MESSAGE';

  /// `AlarmClock.EXTRA_DAYS` (`ArrayList<Integer>` of `Calendar` weekdays).
  static const extraDays = 'android.intent.extra.alarm.DAYS';

  /// `AlarmClock.EXTRA_LENGTH` (seconds, 1–86 400).
  static const extraLength = 'android.intent.extra.alarm.LENGTH';

  /// `AlarmClock.EXTRA_SKIP_UI`.
  static const extraSkipUi = 'android.intent.extra.alarm.SKIP_UI';

  /// Longest timer the intent accepts.
  static const maxTimer = Duration(hours: 24);

  @override
  bool get supportsCancel => false;

  @override
  Future<bool> isAvailable() async =>
      await _resolves(_intent(actionSetAlarm)) &&
      await _resolves(_intent(actionSetTimer));

  @override
  Future<String?> setAlarm({
    required int hour,
    required int minute,
    String? label,
    Set<int>? days,
  }) async {
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    RangeError.checkValueInInterval(minute, 0, 59, 'minute');
    for (final d in days ?? const <int>{}) {
      RangeError.checkValueInInterval(d, 1, 7, 'days');
    }
    final sorted = (days ?? const <int>{}).toList()..sort();
    await _launch(
      _intent(actionSetAlarm, {
        extraHour: hour,
        extraMinutes: minute,
        if (label != null && label.isNotEmpty) extraMessage: label,
        if (sorted.isNotEmpty)
          extraDays: [for (final d in sorted) calendarWeekday(d)],
        extraSkipUi: true,
      }),
    );
    return null;
  }

  @override
  Future<String?> setTimer({required Duration duration, String? label}) async {
    if (duration < const Duration(seconds: 1) || duration > maxTimer) {
      throw ArgumentError.value(duration, 'duration', '1 s bis 24 h');
    }
    await _launch(
      _intent(actionSetTimer, {
        extraLength: duration.inSeconds,
        if (label != null && label.isNotEmpty) extraMessage: label,
        extraSkipUi: true,
      }),
    );
    return null;
  }

  @override
  Future<void> cancel(String id) async => throw const PortException(
    PortErrorKind.unsupported,
    'Gestellte Wecker lassen sich nur in der Uhr-App löschen.',
  );

  @override
  Future<List<AlarmInfo>?> listAlarms() async => null;

  /// ISO weekday (1 = Monday … 7 = Sunday) to `java.util.Calendar`
  /// (1 = Sunday … 7 = Saturday).
  static int calendarWeekday(int isoDay) => isoDay % 7 + 1;

  AndroidIntent _intent(String action, [Map<String, Object?>? args]) =>
      AndroidIntent(action: action, arguments: args, platform: _platform);

  Future<bool> _resolves(AndroidIntent intent) async {
    try {
      return await intent.canResolveActivity() ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _launch(AndroidIntent intent) async {
    if (!await _resolves(intent)) {
      throw const PortException(
        PortErrorKind.unavailable,
        'Keine Uhr-App gefunden, die Wecker stellen kann.',
      );
    }
    try {
      await intent.launch();
    } on PlatformException catch (e) {
      throw PortException(
        PortErrorKind.failed,
        'Die Uhr-App hat den Auftrag abgelehnt (${e.code}).',
      );
    }
  }
}
