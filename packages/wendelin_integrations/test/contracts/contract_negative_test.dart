// Die Contract-Suiten erkennen fehlerhafte Implementierungen: Jede Variante
// unten hat genau einen Defekt und muss die passende Prüfung nicht bestehen.
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

final Matcher _fails = throwsA(isA<TestFailure>());

/// Calendar fake with switchable defects.
final class _BadCalendar implements CalendarPort {
  _BadCalendar({
    this.closedInterval = false,
    this.ignoresFilter = false,
    this.newIdOnUpdate = false,
    this.silentDelete = false,
    this.dropsLocation = false,
    this.shiftsAllDay = false,
    this.writesReadOnly = false,
    this.duplicateIds = false,
  }) : inner = FakeCalendarPort(
         calendars: [
           const CalendarInfo(id: 'privat', name: 'Privat', writable: true),
           const CalendarInfo(id: 'abo', name: 'Abo', writable: false),
           if (duplicateIds)
             const CalendarInfo(id: 'privat', name: 'Doppelt', writable: true),
         ],
       );

  final FakeCalendarPort inner;
  final bool closedInterval;
  final bool ignoresFilter;
  final bool newIdOnUpdate;
  final bool silentDelete;
  final bool dropsLocation;
  final bool shiftsAllDay;
  final bool writesReadOnly;
  final bool duplicateIds;

  @override
  Future<bool> hasPermission() => inner.hasPermission();

  @override
  Future<List<CalendarInfo>> listCalendars() => inner.listCalendars();

  @override
  Future<String?> defaultCalendarId() => inner.defaultCalendarId();

  @override
  Future<List<CalendarEvent>> listEvents(
    TimeRange range, {
    Set<String>? calendarIds,
  }) async {
    final widened = closedInterval
        ? TimeRange(
            range.start.subtract(const Duration(microseconds: 1)),
            range.end.add(const Duration(microseconds: 1)),
          )
        : range;
    return inner.listEvents(
      widened,
      calendarIds: ignoresFilter ? null : calendarIds,
    );
  }

  @override
  Future<CalendarEvent?> getEvent(String id) => inner.getEvent(id);

  @override
  Future<CalendarEvent> createEvent(CalendarEventDraft draft) {
    var d = draft;
    if (writesReadOnly && d.calendarId == 'abo') {
      d = CalendarEventDraft(
        calendarId: 'privat',
        title: d.title,
        start: d.start,
        end: d.end,
      );
    }
    if (dropsLocation || shiftsAllDay) {
      d = CalendarEventDraft(
        calendarId: d.calendarId,
        title: d.title,
        start: shiftsAllDay && d.allDay
            ? d.start.add(const Duration(hours: 2))
            : d.start,
        end: d.end,
        allDay: d.allDay,
        description: d.description,
        location: dropsLocation ? null : d.location,
      );
    }
    return inner.createEvent(d);
  }

  @override
  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    if (newIdOnUpdate) {
      await inner.deleteEvent(event.id);
      return inner.createEvent(
        CalendarEventDraft(
          calendarId: event.calendarId,
          title: event.title,
          start: event.start,
          end: event.end,
        ),
      );
    }
    return inner.updateEvent(event);
  }

  @override
  Future<void> deleteEvent(String id) async {
    if (silentDelete && await inner.getEvent(id) == null) return;
    return inner.deleteEvent(id);
  }
}

final class _TrimmingClipboard implements ClipboardPort {
  final inner = FakeClipboardPort();

  @override
  Future<String?> read() => inner.read();

  @override
  Future<void> write(String text) => inner.write(text.trim());
}

final class _DeafTorch implements TorchPort {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> state() async => false;

  @override
  Future<void> set(bool on) async {}
}

final class _BadAlarms implements AlarmPort {
  _BadAlarms({
    this.noValidation = false,
    this.cancelNoop = false,
    this.claimsCancelWithoutIds = false,
  });

  final bool noValidation;
  final bool cancelNoop;
  final bool claimsCancelWithoutIds;
  final inner = FakeAlarmPort();

  @override
  Future<bool> isAvailable() => inner.isAvailable();

  @override
  bool get supportsCancel => true;

  @override
  Future<String?> setAlarm({
    required int hour,
    required int minute,
    String? label,
    Set<int>? days,
  }) async {
    final id = await inner.setAlarm(
      hour: noValidation ? hour.clamp(0, 23) : hour,
      minute: noValidation ? minute.clamp(0, 59) : minute,
      label: label,
      days: noValidation ? days?.map((d) => d.clamp(1, 7)).toSet() : days,
    );
    return claimsCancelWithoutIds ? null : id;
  }

  @override
  Future<String?> setTimer({required Duration duration, String? label}) =>
      inner.setTimer(
        duration: noValidation && duration <= Duration.zero
            ? const Duration(seconds: 1)
            : duration,
        label: label,
      );

  @override
  Future<void> cancel(String id) async {
    if (cancelNoop) return;
    return inner.cancel(id);
  }

  @override
  Future<List<AlarmInfo>?> listAlarms() => inner.listAlarms();
}

final class _BadMemory implements MemoryStorePort {
  _BadMemory({
    this.storesSensitive = false,
    this.silentForget = false,
    this.dropsFloor = false,
    this.ignoresOwner = false,
  });

  final bool ignoresOwner;
  final bool storesSensitive;
  final bool dropsFloor;
  final bool silentForget;
  final inner = FakeMemoryStore();
  final List<MemoryEntry> raw = [];

  @override
  Future<MemoryEntry> save(
    String text, {
    required MemoryCategory category,
    required String source,
    PrivacyLevel? privacyFloor,
    String owner = '',
  }) async {
    if (storesSensitive && detectSensitiveContent(text) != null) {
      final e = MemoryEntry(
        id: 'raw${raw.length}',
        text: text,
        category: category,
        source: source,
        createdAt: DateTime.utc(2026),
      );
      raw.add(e);
      return e;
    }
    return inner.save(
      text,
      category: category,
      source: source,
      privacyFloor: dropsFloor ? null : privacyFloor,
      owner: ignoresOwner ? '' : owner,
    );
  }

  @override
  Future<List<MemoryEntry>> search(
    String query, {
    int limit = 5,
    String owner = '',
  }) => inner.search(query, limit: limit, owner: owner);

  @override
  Future<MemoryEntry> forget(String id, {String owner = ''}) async {
    if (silentForget && !(await inner.list()).any((e) => e.id == id)) {
      return MemoryEntry(
        id: id,
        text: '',
        category: MemoryCategory.fact,
        source: '',
        createdAt: DateTime.utc(2026),
      );
    }
    return inner.forget(id, owner: owner);
  }

  @override
  Future<List<MemoryEntry>> list({String owner = ''}) async => [
    if (owner.isEmpty) ...raw,
    ...await inner.list(owner: owner),
  ];
}

/// List file port with switchable defects.
final class _BadListFile implements ListFilePort {
  _BadListFile({this.appends = false, this.normalizesNewlines = false});

  final bool appends;
  final bool normalizesNewlines;
  final files = <String, String>{};

  @override
  Future<bool> exists(String handle) async => files.containsKey(handle);

  @override
  Future<String> read(String handle) async =>
      files[handle] ??
      (throw const PortException(PortErrorKind.notFound, 'fehlt'));

  @override
  Future<void> write(String handle, String content) async {
    var c = normalizesNewlines ? content.replaceAll('\r\n', '\n') : content;
    // Defekt wie SAF-Modus "w" ohne "t": alter Rest bleibt stehen.
    final old = files[handle];
    if (appends && old != null && old.length > c.length) {
      c = c + old.substring(c.length);
    }
    files[handle] = c;
  }
}

final class _LeakyBackend implements WebSearchBackend {
  @override
  String get id => 'leaky';

  @override
  String get displayName => 'Leaky';

  @override
  Future<List<WebSearchResult>> search(
    String query, {
    int count = 5,
    String? language,
    CancelToken? cancel,
  }) async => throw const PortException(
    PortErrorKind.unavailable,
    'Schlüssel $webSearchContractKey ungültig',
  );
}

void main() {
  group('calendarPortContract erkennt', () {
    test('korrekte Variante besteht alle Prüfungen', () async {
      for (final check in calendarPortContractChecks(_BadCalendar.new).values) {
        await check();
      }
    });

    for (final (label, port, check) in [
      (
        'geschlossenes Intervall',
        () => _BadCalendar(closedInterval: true),
        CalendarPortChecks.listOverlap,
      ),
      (
        'ignorierter Kalenderfilter',
        () => _BadCalendar(ignoresFilter: true),
        CalendarPortChecks.listOverlap,
      ),
      (
        'neue Id beim Ändern',
        () => _BadCalendar(newIdOnUpdate: true),
        CalendarPortChecks.update,
      ),
      (
        'stilles Löschen unbekannter Ids',
        () => _BadCalendar(silentDelete: true),
        CalendarPortChecks.delete,
      ),
      (
        'verlorener Ort',
        () => _BadCalendar(dropsLocation: true),
        CalendarPortChecks.create,
      ),
      (
        'verschobener ganztägiger Termin',
        () => _BadCalendar(shiftsAllDay: true),
        CalendarPortChecks.allDay,
      ),
      (
        'schreibgeschützter Kalender beschrieben',
        () => _BadCalendar(writesReadOnly: true),
        CalendarPortChecks.readOnly,
      ),
      (
        'doppelte Kalender-Ids',
        () => _BadCalendar(duplicateIds: true),
        CalendarPortChecks.calendars,
      ),
    ]) {
      test(label, () async {
        await expectLater(calendarPortContractChecks(port)[check]!(), _fails);
      });
    }

    test('fehlende Berechtigung als Vorbedingung', () async {
      await expectLater(
        calendarPortContractChecks(
          () => FakeCalendarPort(permissionGranted: false),
        )[CalendarPortChecks.create]!(),
        _fails,
      );
    });
  });

  test('clipboardPortContract erkennt Kürzen von Leerraum', () async {
    final checks = clipboardPortContractChecks(_TrimmingClipboard.new);
    await checks[ClipboardPortChecks.roundTrip]!();
    await expectLater(checks[ClipboardPortChecks.unicode]!(), _fails);
  });

  test('torchPortContract erkennt einen Port, der set ignoriert', () async {
    final checks = torchPortContractChecks(_DeafTorch.new);
    await expectLater(checks[TorchPortChecks.roundTrip]!(), _fails);
  });

  group('alarmPortContract erkennt', () {
    test('fehlende Prüfung der Werte', () async {
      await expectLater(
        alarmPortContractChecks(
          () => _BadAlarms(noValidation: true),
        )[AlarmPortChecks.invalid]!(),
        _fails,
      );
    });

    test('supportsCancel ohne Ids', () async {
      await expectLater(
        alarmPortContractChecks(
          () => _BadAlarms(claimsCancelWithoutIds: true),
        )[AlarmPortChecks.alarmLifecycle]!(),
        _fails,
      );
    });

    test('ohne Abbrechbarkeit legt die Suite nichts an', () async {
      final port = FakeAlarmPort(returnsIds: false);
      for (final check in alarmPortContractChecks(() => port).values) {
        await check();
      }
      expect(port.alarms, isEmpty);
      expect(port.timers, isEmpty);
    });

    test('wirkungsloses cancel', () async {
      final checks = alarmPortContractChecks(
        () => _BadAlarms(cancelNoop: true),
      );
      await expectLater(checks[AlarmPortChecks.alarmLifecycle]!(), _fails);
      await expectLater(checks[AlarmPortChecks.unknownCancel]!(), _fails);
    });
  });

  group('listFilePortContract erkennt', () {
    ListFileContractSetup setup(_BadListFile p) =>
        (port: p, newHandle: () => 'x.md', delete: null, reopen: null);

    test('nicht persistierende Instanz', () async {
      await expectLater(
        listFilePortContractChecks(
          () => (
            port: _BadListFile(),
            newHandle: () => 'x.md',
            delete: null,
            reopen: _BadListFile.new,
          ),
        )[ListFilePortChecks.persisted]!(),
        _fails,
      );
    });

    test('korrekte Variante besteht alle Prüfungen', () async {
      for (final check in listFilePortContractChecks(
        () => setup(_BadListFile()),
      ).values) {
        await check();
      }
    });

    test('Überschreiben ohne Kürzen', () async {
      await expectLater(
        listFilePortContractChecks(
          () => setup(_BadListFile(appends: true)),
        )[ListFilePortChecks.truncate]!(),
        _fails,
      );
    });

    test('umgeschriebene Zeilenenden', () async {
      await expectLater(
        listFilePortContractChecks(
          () => setup(_BadListFile(normalizesNewlines: true)),
        )[ListFilePortChecks.exact]!(),
        _fails,
      );
    });
  });

  group('memoryStoreContract erkennt', () {
    test('gespeicherte sensible Inhalte', () async {
      await expectLater(
        memoryStoreContractChecks(
          () => _BadMemory(storesSensitive: true),
        )[MemoryStoreChecks.sensitive]!(),
        _fails,
      );
    });

    test('verlorene Untergrenze', () async {
      await expectLater(
        memoryStoreContractChecks(
          () => _BadMemory(dropsFloor: true),
        )[MemoryStoreChecks.privacyFloor]!(),
        _fails,
      );
    });

    test('vermischte Namespaces', () async {
      await expectLater(
        memoryStoreContractChecks(
          () => _BadMemory(ignoresOwner: true),
        )[MemoryStoreChecks.owners]!(),
        _fails,
      );
    });

    test('stilles Vergessen unbekannter Ids', () async {
      await expectLater(
        memoryStoreContractChecks(
          () => _BadMemory(silentForget: true),
        )[MemoryStoreChecks.forget]!(),
        _fails,
      );
    });
  });

  test(
    'webSearchBackendContract erkennt Schlüssel in Fehlermeldungen',
    () async {
      await expectLater(
        webSearchBackendContractChecks(
          (_) => _LeakyBackend(),
        )[WebSearchChecks.unauthorized]!(),
        _fails,
      );
    },
  );
}
