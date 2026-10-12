import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/device_calendar_port.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

const _channel = MethodChannel(DeviceCalendarPort.channelName);

/// Dart stand-in for `CalendarChannel.kt`: same methods, arguments and
/// error codes. Like `CalendarContract.Instances` it returns events that
/// merely touch the queried range; the port must filter.
final class _FakeNative {
  bool permission = true;
  bool grantOnRequest = true;
  int requests = 0;
  final calendars = <Map<String, Object?>>[
    {'id': '1', 'name': 'Privat', 'writable': true, 'primary': false},
    {'id': '2', 'name': 'Familie', 'writable': true, 'primary': true},
    {'id': '3', 'name': 'Feiertage', 'writable': false, 'primary': false},
  ];
  final events = <String, Map<String, Object?>>{};
  final calls = <MethodCall>[];
  var _next = 100;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final a = (call.arguments as Map<Object?, Object?>?) ?? const {};
    switch (call.method) {
      case 'hasPermission':
        return permission;
      case 'requestPermission':
        requests++;
        if (grantOnRequest) permission = true;
        return permission;
    }
    if (!permission) throw PlatformException(code: 'permissionDenied');
    switch (call.method) {
      case 'listCalendars':
        return calendars;
      case 'listEvents':
        final ids = (a['calendarIds'] as List<Object?>?)?.toSet();
        return [
          for (final e in events.values)
            if ((e['start']! as int) <= (a['end']! as int) &&
                (e['end']! as int) >= (a['start']! as int) &&
                (ids == null || ids.contains(e['calendarId'])))
              e,
        ];
      case 'getEvent':
        return events[a['id']];
      case 'createEvent':
        final cal = calendars.where((c) => c['id'] == a['calendarId']);
        if (cal.isEmpty) throw PlatformException(code: 'notFound');
        if (cal.single['writable'] != true) {
          throw PlatformException(code: 'readOnly');
        }
        final id = '${_next++}';
        return events[id] = _stored(id, a);
      case 'updateEvent':
        final id = a['id']! as String;
        if (!events.containsKey(id)) throw PlatformException(code: 'notFound');
        return events[id] = _stored(id, a);
      case 'deleteEvent':
        if (events.remove(a['id']) == null) {
          throw PlatformException(code: 'notFound');
        }
        return null;
    }
    throw MissingPluginException(call.method);
  }

  static Map<String, Object?> _stored(String id, Map<Object?, Object?> a) => {
    'id': id,
    'calendarId': a['calendarId'],
    'title': a['title'],
    'start': a['start'],
    'end': a['end'],
    'allDay': a['allDay'],
    'location': a['location'] ?? '',
    'description': a['description'] ?? '',
    'attendees': <String>[],
    'busy': true,
    'recurring': false,
    'timeZone': a['timeZone'],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeNative native;

  setUp(() {
    native = _FakeNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, native.handle);
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null),
  );

  calendarPortContract(DeviceCalendarPort.new, name: 'DeviceCalendarPort');

  Matcher port(PortErrorKind kind) =>
      throwsA(isA<PortException>().having((e) => e.kind, 'kind', kind));

  group('Standardkalender', () {
    test('ohne Wahl: primärer beschreibbarer Kalender', () async {
      expect(await DeviceCalendarPort().defaultCalendarId(), '2');
    });

    test('Wahl des Nutzers gewinnt, wenn beschreibbar', () async {
      expect(
        await DeviceCalendarPort(preferredCalendar: () async => '1')
            .defaultCalendarId(),
        '1',
      );
    });

    test('schreibgeschützte oder unbekannte Wahl wird ignoriert', () async {
      for (final pick in ['3', 'weg']) {
        expect(
          await DeviceCalendarPort(preferredCalendar: () async => pick)
              .defaultCalendarId(),
          '2',
        );
      }
    });

    test(
      'ohne primären: erster beschreibbarer; ohne beschreibbare: null',
      () async {
        native.calendars[1]['primary'] = false;
        expect(await DeviceCalendarPort().defaultCalendarId(), '1');
        for (final c in native.calendars) {
          c['writable'] = false;
        }
        expect(await DeviceCalendarPort().defaultCalendarId(), isNull);
      },
    );
  });

  group('Berechtigung', () {
    test('wird nur über requestPermission angefragt', () async {
      native.permission = false;
      final p = DeviceCalendarPort();
      expect(await p.hasPermission(), isFalse);
      expect(native.requests, 0);
      expect(await p.requestPermission(), isTrue);
      expect(native.requests, 1);
      expect(await p.hasPermission(), isTrue);
    });

    test('abgelehnt: Aufrufe melden permissionDenied', () async {
      native
        ..permission = false
        ..grantOnRequest = false;
      final p = DeviceCalendarPort();
      expect(await p.requestPermission(), isFalse);
      await expectLater(
        p.listCalendars(),
        port(PortErrorKind.permissionDenied),
      );
    });
  });

  test('listEvents fragt mit Puffer und filtert halboffen', () async {
    final p = DeviceCalendarPort();
    final start = DateTime.utc(2031, 3, 10, 9);
    final e = await p.createEvent(
      CalendarEventDraft(
        calendarId: '1',
        title: 'Tauchen',
        start: start,
        end: start.add(const Duration(hours: 1)),
      ),
    );
    final before = TimeRange(start.subtract(const Duration(hours: 1)), start);
    expect(await p.listEvents(before), isEmpty);
    final query = native.calls.lastWhere((c) => c.method == 'listEvents');
    final args = query.arguments as Map<Object?, Object?>;
    expect(
      args['start'],
      before.start.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    expect(
      args['end'],
      before.end.add(const Duration(days: 1)).millisecondsSinceEpoch,
    );
    expect(
      (await p.listEvents(
        TimeRange(start, start.add(const Duration(minutes: 1))),
      )).single.id,
      e.id,
    );
  });

  test('Termin-Felder werden übertragen und gelesen', () async {
    final p = DeviceCalendarPort();
    final day = DateTime.utc(2031, 3, 12);
    final e = await p.createEvent(
      CalendarEventDraft(
        calendarId: '1',
        title: 'Urlaub',
        start: day,
        end: day.add(const Duration(days: 1)),
        allDay: true,
        timeZone: 'Europe/Berlin',
      ),
    );
    final sent = native.calls.lastWhere((c) => c.method == 'createEvent');
    expect((sent.arguments as Map<Object?, Object?>)['timeZone'], 'UTC');
    expect(e.allDay, isTrue);
    expect(e.start, day);
    expect(e.location, isNull, reason: 'leerer Ort wird null');
    expect(e.attendees, isEmpty);
    expect(e.busy, isTrue);
  });

  test('Ende vor Beginn wird ohne Plattformaufruf abgelehnt', () async {
    final start = DateTime.utc(2031, 3, 10, 9);
    await expectLater(
      DeviceCalendarPort().createEvent(
        CalendarEventDraft(
          calendarId: '1',
          title: 'x',
          start: start,
          end: start,
        ),
      ),
      port(PortErrorKind.rejected),
    );
    expect(native.calls.where((c) => c.method == 'createEvent'), isEmpty);
  });

  test('Fehlercodes werden zu deutschen PortExceptions', () {
    for (final (code, kind) in [
      ('permissionDenied', PortErrorKind.permissionDenied),
      ('notFound', PortErrorKind.notFound),
      ('readOnly', PortErrorKind.readOnly),
      ('failed', PortErrorKind.failed),
      ('unbekannt', PortErrorKind.failed),
    ]) {
      final e = DeviceCalendarPort.portExceptionFor(code);
      expect(e.kind, kind, reason: code);
      expect(e.message, isNotEmpty);
    }
  });

  test('ohne Plattform-Implementierung: unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    await expectLater(
      DeviceCalendarPort().listCalendars(),
      port(PortErrorKind.unsupported),
    );
  });
}
