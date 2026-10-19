// Gerätetest (WP11): „Trag mir morgen um 10 Tauchen ein“ über die echte
// App-Verdrahtung und den Kotlin-Kanal `CalendarChannel.kt` in den
// Gerätekalender (CalendarContract), Rückgängig, und das external-Tool
// `calendar__delete_event` mit Bestätigungs-Sheet (Nein/Ja).
//
// Voraussetzungen (übernimmt `tool/e2e_android.sh`): AOSP-Emulator ohne
// Google Play, ein lokaler Kalender, Kalender-Berechtigung per
// `adb shell pm grant`. Der Provider ist der Skript-Provider der Demo
// (kein Netz, kein Key), die Ports sind die echten Geräte-Ports.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/provider_config.dart';
import 'package:wendelin/platform/device_calendar_port.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/screens/confirmation_sheet.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'support/e2e.dart';

/// Title used by this test; events with it are removed before and after.
const _title = 'Tauchen';

Future<List<CalendarEvent>> _tomorrowDiving(DeviceCalendarPort port) async {
  final events = await port.listEvents(
    TimeRange(e2eTomorrow, e2eTomorrow.add(const Duration(days: 1))),
  );
  return events.where((e) => e.title == _title).toList();
}

Future<void> _cleanUp(DeviceCalendarPort port) async {
  for (final e in await _tomorrowDiving(port)) {
    await port.deleteEvent(e.id);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final port = DeviceCalendarPort();

  setUpAll(() async {
    await expectCalendarPermission(port);
    final calendars = await port.listCalendars();
    expect(
      calendars.where((c) => c.writable),
      isNotEmpty,
      reason: 'Kein beschreibbarer Kalender (lokalen Kalender anlegen)',
    );
    await _cleanUp(port);
  });
  tearDownAll(() => _cleanUp(port));

  testWidgets('Kanal: anlegen, lesen, ändern, löschen im Gerätekalender', (
    tester,
  ) async {
    final calendarId = (await port.defaultCalendarId())!;
    final start = e2eNow.add(const Duration(days: 3, hours: 2));
    final created = await port.createEvent(
      CalendarEventDraft(
        calendarId: calendarId,
        title: 'Kanaltest',
        start: start,
        end: start.add(const Duration(minutes: 45)),
        location: 'Hafen',
        timeZone: 'Europe/Berlin',
      ),
    );
    addTearDown(() async {
      if (await port.getEvent(created.id) != null) {
        await port.deleteEvent(created.id);
      }
    });
    expect(created.title, 'Kanaltest');
    expect(created.calendarId, calendarId);
    expect(created.location, 'Hafen');
    expect(created.start.millisecondsSinceEpoch, start.millisecondsSinceEpoch);
    expect(created.end.difference(created.start).inMinutes, 45);
    expect(created.recurring, isFalse);

    final listed = await port.listEvents(
      TimeRange(
        start.subtract(const Duration(hours: 1)),
        start.add(const Duration(hours: 1)),
      ),
      calendarIds: {calendarId},
    );
    expect(listed.map((e) => e.id), contains(created.id));

    final moved = await port.updateEvent(
      created.copyWith(
        title: 'Kanaltest 2',
        location: null,
        end: created.end.add(const Duration(minutes: 15)),
      ),
    );
    expect(moved.title, 'Kanaltest 2');
    expect(moved.end.difference(moved.start).inMinutes, 60);

    await port.deleteEvent(created.id);
    expect(await port.getEvent(created.id), isNull);
    final after = await port.listEvents(
      TimeRange(
        start.subtract(const Duration(hours: 1)),
        start.add(const Duration(hours: 1)),
      ),
    );
    expect(after.map((e) => e.id), isNot(contains(created.id)));
    await expectLater(
      port.deleteEvent(created.id),
      throwsA(
        isA<PortException>().having(
          (e) => e.kind,
          'kind',
          PortErrorKind.notFound,
        ),
      ),
    );
  });

  testWidgets('Kanal: ganztägiger Termin liegt am richtigen Tag', (
    tester,
  ) async {
    final calendarId = (await port.defaultCalendarId())!;
    final day = DateTime.utc(e2eNow.year, e2eNow.month, e2eNow.day + 4);
    final created = await port.createEvent(
      CalendarEventDraft(
        calendarId: calendarId,
        title: 'Kanaltest ganztägig',
        start: day,
        end: day.add(const Duration(days: 1)),
        allDay: true,
      ),
    );
    addTearDown(() => port.deleteEvent(created.id));
    expect(created.allDay, isTrue);
    expect(created.start, day);
    final local = DateTime(day.year, day.month, day.day);
    final sameDay = await port.listEvents(
      TimeRange(
        local.add(const Duration(hours: 12)),
        local.add(const Duration(hours: 13)),
      ),
    );
    expect(sameDay.map((e) => e.id), contains(created.id));
    final dayBefore = await port.listEvents(
      TimeRange(
        local.subtract(const Duration(hours: 12)),
        local.subtract(const Duration(hours: 11)),
      ),
    );
    expect(dayBefore.map((e) => e.id), isNot(contains(created.id)));
  });

  testWidgets(
    '„Trag mir morgen um 10 Tauchen ein“ → Gerätekalender → Rückgängig',
    (tester) async {
      final app = E2eApp(
        config: ProviderConfig.demo,
        clock: FixedClock(e2eNow),
      );
      await app.pump(tester);

      await send(tester, 'Trag mir morgen um 10 Tauchen ein');
      await pumpUntil(tester, find.textContaining('steht im Kalender'));
      expect(
        find.descendant(
          of: find.byType(ToolResultCard),
          matching: find.text('Termin angelegt'),
        ),
        findsOneWidget,
      );

      final events = await _tomorrowDiving(port);
      expect(events, hasLength(1), reason: 'Termin im Gerätekalender');
      final event = events.single;
      final local = event.start.toLocal();
      expect((local.hour, local.minute), (10, 0));
      expect(event.end.difference(event.start), const Duration(hours: 1));

      final undo = undoButton(tester);
      expect(undo, findsOneWidget);
      await tester.tap(undo);
      await pumpUntil(tester, find.text(l10n(tester).toolResultUndone));
      expect(await port.getEvent(event.id), isNull);
      expect(await _tomorrowDiving(port), isEmpty);
      final audit = await auditText(app);
      expect(audit, contains('calendar__create_event'));
      expect(audit, contains('undo: true'), reason: 'Rückgängig im Audit-Log');
    },
  );

  testWidgets('calendar__delete_event fragt nach: Nein behält, Ja löscht', (
    tester,
  ) async {
    final app = E2eApp(config: ProviderConfig.demo, clock: FixedClock(e2eNow));
    await app.pump(tester);

    await send(tester, 'Trag mir morgen um 10 Tauchen ein');
    await pumpUntil(tester, find.textContaining('steht im Kalender'));
    final id = (await _tomorrowDiving(port)).single.id;

    await send(tester, 'Lösch den Termin');
    await pumpUntil(tester, find.byType(ConfirmationSheet));
    await pumpUntil(tester, find.text(l10n(tester).mainNoKeep));
    await pumpFor(tester);
    expect(find.text(l10n(tester).mainDeleteEventTitle), findsOneWidget);
    expect(
      find.textContaining(_title),
      findsWidgets,
      reason: 'Bestätigung nennt den Termin (live nachgeschlagen)',
    );
    await tester.tap(find.text(l10n(tester).mainNoKeep));
    await pumpUntil(tester, find.text('Gut, ich lasse alles, wie es ist.'));
    expect(await port.getEvent(id), isNotNull, reason: '„Nein“ behält ihn');

    await send(tester, 'Lösch den Termin');
    await pumpUntil(tester, find.text(l10n(tester).mainYesDelete));
    await pumpFor(tester);
    await tester.tap(find.text(l10n(tester).mainYesDelete));
    await pumpUntil(tester, find.text('Erledigt, der Termin ist gelöscht.'));
    expect(await port.getEvent(id), isNull, reason: '„Ja“ löscht ihn');
    expect(await auditText(app), contains('calendar__delete_event'));
  });
}
