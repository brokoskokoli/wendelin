import 'package:flutter/services.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'channels.dart';

/// Reads the calendar the user chose for new events (settings), or `null`.
typedef PreferredCalendar = Future<String?> Function();

/// [CalendarPort] on Android's `CalendarContract` through the platform
/// channel [channelName] (Kotlin side: `CalendarChannel.kt`).
///
/// The native side only does plain queries and writes; this class adds the
/// port semantics: half-open overlap and calendar filter for [listEvents],
/// the choice of the default calendar, and German [PortException]s from the
/// native error codes. The permission is requested only through
/// [requestPermission], when the user enables the calendar integration.
final class DeviceCalendarPort implements CalendarPort {
  /// Creates the port; `channel` is injectable for tests.
  DeviceCalendarPort({
    PreferredCalendar? preferredCalendar,
    this._channel = const MethodChannel(calendarChannelName),
  }) : _preferred = preferredCalendar;

  /// Name of the platform channel.
  static const channelName = calendarChannelName;

  final MethodChannel _channel;
  final PreferredCalendar? _preferred;

  /// Asks the user for calendar access (read and write); returns whether it
  /// is granted afterwards.
  Future<bool> requestPermission() async =>
      await _call<bool>('requestPermission') ?? false;

  @override
  Future<bool> hasPermission() async =>
      await _call<bool>('hasPermission') ?? false;

  @override
  Future<List<CalendarInfo>> listCalendars() async => [
    for (final m in await _list('listCalendars')) _calendar(m),
  ];

  @override
  Future<String?> defaultCalendarId() async {
    final raw = await _list('listCalendars');
    final writable = raw.where((m) => m['writable'] == true).toList();
    if (writable.isEmpty) return null;
    final preferred = await _preferred?.call();
    bool has(String? id) => writable.any((m) => m['id'] == id);
    if (has(preferred)) return preferred;
    final primary = writable.where((m) => m['primary'] == true);
    return (primary.isEmpty ? writable.first : primary.first)['id']! as String;
  }

  @override
  Future<List<CalendarEvent>> listEvents(
    TimeRange range, {
    Set<String>? calendarIds,
  }) async {
    // Native instance queries include touching events and expand all-day
    // events in UTC; query a day more on each side and filter here. The
    // calendar filter is applied natively.
    const pad = Duration(days: 1);
    final raw = await _list('listEvents', {
      'start': range.start.subtract(pad).millisecondsSinceEpoch,
      'end': range.end.add(pad).millisecondsSinceEpoch,
      if (calendarIds != null) 'calendarIds': calendarIds.toList(),
    });
    final events = [for (final m in raw) _event(m)]
        .where((e) => e.range.overlaps(range))
        .toList();
    return events..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<CalendarEvent?> getEvent(String id) async {
    final m = await _call<Map<Object?, Object?>>('getEvent', {'id': id});
    return m == null ? null : _event(m);
  }

  @override
  Future<CalendarEvent> createEvent(CalendarEventDraft draft) async {
    if (!draft.end.isAfter(draft.start)) {
      throw const PortException(
        PortErrorKind.rejected,
        'Ende muss nach dem Beginn liegen',
      );
    }
    final m = await _call<Map<Object?, Object?>>('createEvent', {
      'calendarId': draft.calendarId,
      ..._fields(
        title: draft.title,
        start: draft.start,
        end: draft.end,
        allDay: draft.allDay,
        location: draft.location,
        description: draft.description,
        timeZone: draft.timeZone,
      ),
    });
    return _event(_required(m));
  }

  @override
  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    final m = await _call<Map<Object?, Object?>>('updateEvent', {
      'id': event.id,
      ..._fields(
        title: event.title,
        start: event.start,
        end: event.end,
        allDay: event.allDay,
        location: event.location,
        description: event.description,
        timeZone: event.timeZone,
      ),
    });
    return _event(_required(m));
  }

  @override
  Future<void> deleteEvent(String id) => _call<void>('deleteEvent', {'id': id});

  static Map<String, Object?> _fields({
    required String title,
    required DateTime start,
    required DateTime end,
    required bool allDay,
    required String? location,
    required String? description,
    required String? timeZone,
  }) => {
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    'allDay': allDay,
    'location': location,
    'description': description,
    'timeZone': allDay ? 'UTC' : timeZone,
  };

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw portExceptionFor(e.code);
    } on MissingPluginException {
      throw const PortException(
        PortErrorKind.unsupported,
        'Kalender ist auf diesem Gerät nicht verfügbar.',
      );
    }
  }

  Future<List<Map<Object?, Object?>>> _list(
    String method, [
    Map<String, Object?>? args,
  ]) async => [
    for (final m in await _call<List<Object?>>(method, args) ?? const [])
      m! as Map<Object?, Object?>,
  ];

  static Map<Object?, Object?> _required(Map<Object?, Object?>? m) =>
      m ??
      (throw const PortException(
        PortErrorKind.failed,
        'Der Kalender hat keinen Termin zurückgegeben.',
      ));

  /// German [PortException] for a native error [code].
  static PortException portExceptionFor(String code) => switch (code) {
    'permissionDenied' => const PortException(
      PortErrorKind.permissionDenied,
      'Kein Zugriff auf den Kalender. Bitte in den Einstellungen erlauben.',
    ),
    'notFound' => const PortException(
      PortErrorKind.notFound,
      'Diesen Termin oder Kalender gibt es nicht.',
    ),
    'readOnly' => const PortException(
      PortErrorKind.readOnly,
      'Dieser Kalender ist schreibgeschützt.',
    ),
    _ => const PortException(
      PortErrorKind.failed,
      'Der Kalender hat einen Fehler gemeldet.',
    ),
  };

  static CalendarInfo _calendar(Map<Object?, Object?> m) => CalendarInfo(
    id: m['id']! as String,
    name: m['name']! as String,
    writable: m['writable'] == true,
    accountName: m['accountName'] as String?,
  );

  static DateTime _utc(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms! as int, isUtc: true);

  static String? _text(Object? v) => v is String && v.isNotEmpty ? v : null;

  static CalendarEvent _event(Map<Object?, Object?> m) => CalendarEvent(
    id: m['id']! as String,
    calendarId: m['calendarId']! as String,
    title: (m['title'] as String?) ?? '',
    start: _utc(m['start']),
    end: _utc(m['end']),
    allDay: m['allDay'] == true,
    location: _text(m['location']),
    description: _text(m['description']),
    attendees: [
      for (final a in (m['attendees'] as List<Object?>?) ?? const [])
        a! as String,
    ],
    busy: m['busy'] != false,
    recurring: m['recurring'] == true,
    timeZone: _text(m['timeZone']),
  );
}
