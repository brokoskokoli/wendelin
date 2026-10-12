import 'package:test/test.dart';
import 'package:wendelin_integrations/src/common/time.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  final berlin = timeZoneLocation('Europe/Berlin');

  group('IsoInput.parse', () {
    final valid = <String, (String, int?, Duration?)>{
      '2026-10-15': ('2026-10-15', null, null),
      '2026-10-15T10:00': ('2026-10-15', 600, null),
      '2026-10-15T10:00:30': ('2026-10-15', 600, null),
      '2026-10-15 10:05': ('2026-10-15', 605, null),
      '2026-10-15T10:00:00.123': ('2026-10-15', 600, null),
      '2026-10-15T10:00Z': ('2026-10-15', 600, Duration.zero),
      '2026-10-15T10:00+02:00': ('2026-10-15', 600, const Duration(hours: 2)),
      '2026-10-15T10:00-0530': (
        '2026-10-15',
        600,
        -const Duration(hours: 5, minutes: 30),
      ),
      '2026-10-15T10:00+01': ('2026-10-15', 600, const Duration(hours: 1)),
      ' 2028-02-29T23:59 ': ('2028-02-29', 23 * 60 + 59, null),
    };
    valid.forEach((input, expected) {
      test('gültig: "$input"', () {
        final p = IsoInput.parse(input, 'start');
        expect(p.date.toIso(), expected.$1);
        expect(p.minutes, expected.$2);
        expect(p.hasTime, expected.$2 != null);
        expect(p.offset, expected.$3);
      });
    });

    for (final input in [
      '',
      'morgen',
      '15.10.2026',
      '2026-13-01',
      '2026-02-30',
      '2027-02-29',
      '2026-10-15T24:00',
      '2026-10-15T10:60',
      '2026-10-15T10',
      '2026-10-15T10:00+19:00',
      '2026-10-15T10:00:61',
    ]) {
      test('ungültig: "$input"', () {
        expect(
          () => IsoInput.parse(input, 'start'),
          throwsA(
            isA<InvalidArgumentsException>().having(
              (e) => e.message,
              'message',
              contains('„start“'),
            ),
          ),
        );
      });
    }
  });

  group('instantIn', () {
    test('ohne Offset: Wandzeit in der Zone (Sommer- und Winterzeit)', () {
      expect(
        IsoInput.parse('2026-07-01T10:00', 's').instantIn(berlin),
        DateTime.utc(2026, 7, 1, 8),
      );
      expect(
        IsoInput.parse('2026-12-01T10:00', 's').instantIn(berlin),
        DateTime.utc(2026, 12, 1, 9),
      );
    });

    test('mit Offset: Zone wird ignoriert', () {
      expect(
        IsoInput.parse('2026-07-01T10:00-04:00', 's').instantIn(berlin),
        DateTime.utc(2026, 7, 1, 14),
      );
      expect(
        IsoInput.parse('2026-07-01T10:00:15Z', 's').instantIn(berlin),
        DateTime.utc(2026, 7, 1, 10, 0, 15),
      );
    });

    test('nur Datum: Mitternacht der Zone', () {
      expect(
        IsoInput.parse('2026-07-01', 's').instantIn(berlin),
        DateTime.utc(2026, 6, 30, 22),
      );
    });

    test('Sommerzeitlücke: 02:30 am 29.03.2026 wird verschoben, nicht '
        'verworfen', () {
      final i = IsoInput.parse('2026-03-29T02:30', 's').instantIn(berlin);
      // 02:00 CET = 01:00 UTC ist der Sprung; die Uhrzeit landet in der Nähe.
      expect(i.isAfter(DateTime.utc(2026, 3, 29, 0, 59)), isTrue);
      expect(i.isBefore(DateTime.utc(2026, 3, 29, 1, 31)), isTrue);
    });
  });

  test('isoInZone mit Offset und Sommerzeitwechsel', () {
    expect(
      isoInZone(DateTime.utc(2026, 10, 25, 0, 30), berlin),
      '2026-10-25T02:30:00+02:00',
    );
    expect(
      isoInZone(DateTime.utc(2026, 10, 25, 1, 30), berlin),
      '2026-10-25T02:30:00+01:00',
    );
    expect(
      isoInZone(DateTime.utc(2026, 1, 5, 3, 4, 5), timeZoneLocation('UTC')),
      '2026-01-05T03:04:05+00:00',
    );
    expect(
      isoInZone(
        DateTime.utc(2026, 1, 5, 12),
        timeZoneLocation('America/St_Johns'),
      ),
      '2026-01-05T08:30:00-03:30',
    );
  });

  test('deutsche Formate', () {
    final start = DateTime.utc(2026, 10, 15, 8);
    expect(germanDay(LocalDate(2026, 10, 15)), 'Do 15.10.');
    expect(germanClock(start, berlin), '10:00');
    expect(germanDateTime(start, berlin), 'Do 15.10. 10:00');
    expect(
      germanSpan(start, start.add(const Duration(hours: 1)), berlin),
      'Do 15.10. 10:00–11:00',
    );
    expect(
      germanSpan(start, start.add(const Duration(hours: 16)), berlin),
      'Do 15.10. 10:00 – Fr 16.10. 02:00',
    );
    expect(
      germanAllDaySpan(LocalDate(2026, 10, 15), LocalDate(2026, 10, 15)),
      'Do 15.10. (ganztägig)',
    );
    expect(
      germanAllDaySpan(LocalDate(2026, 10, 18), LocalDate(2026, 10, 19)),
      'So 18.10.–Mo 19.10. (ganztägig)',
    );
  });

  test('parseClockTime', () {
    expect(parseClockTime('08:30', 'x'), 510);
    expect(parseClockTime('8:05', 'x'), 485);
    expect(parseClockTime('24:00', 'x'), 1440);
    expect(parseClockTime('00:00', 'x'), 0);
    for (final bad in ['24:01', '25:00', '7', '07:60', 'acht']) {
      expect(
        () => parseClockTime(bad, 'x'),
        throwsA(isA<InvalidArgumentsException>()),
        reason: bad,
      );
    }
  });

  test('timeZoneLocation: UTC, IANA, unbekannt', () {
    expect(timeZoneLocation('UTC'), same(timeZoneLocation('Etc/UTC')));
    expect(timeZoneLocation('Z'), same(timeZoneLocation('UTC')));
    expect(timeZoneLocation('Europe/Lisbon').name, 'Europe/Lisbon');
    expect(
      () => timeZoneLocation('Mars/Olympus'),
      throwsA(isA<InvalidArgumentsException>()),
    );
  });

  test('LocalDate: Arithmetik, Wochentag, Vergleich, Zone', () {
    final d = LocalDate(2026, 12, 31);
    expect(d.addDays(1), LocalDate(2027, 1, 1));
    expect(d.addDays(-365).toIso(), '2025-12-31');
    expect(d.weekday, DateTime.thursday);
    expect(d.compareTo(d.addDays(1)), lessThan(0));
    expect(d.hashCode, LocalDate(2026, 12, 31).hashCode);
    expect(d.toString(), '2026-12-31');
    expect(
      LocalDate.of(DateTime.utc(2026, 12, 31, 23, 30), berlin),
      LocalDate(2027, 1, 1),
    );
    expect(
      LocalDate(2026, 3, 29).startIn(berlin),
      DateTime.utc(2026, 3, 28, 23),
    );
    expect(
      LocalDate(2026, 3, 29).atMinutes(24 * 60, berlin),
      DateTime.utc(2026, 3, 29, 22),
    );
  });
}
