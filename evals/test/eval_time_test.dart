import 'package:test/test.dart';
import 'package:wendelin_evals/wendelin_evals.dart';

void main() {
  // Mittwoch, 14.10.2026, 09:00 Europe/Berlin (UTC+2).
  final time = EvalTime.parse('2026-10-14T09:00', 'Europe/Berlin');

  group('EvalTime.resolve', () {
    final table = <String, String>{
      'today': '2026-10-14',
      'tomorrow 10:00': '2026-10-15T10:00',
      'yesterday': '2026-10-13',
      '+1d 10:00': '2026-10-15T10:00',
      '+2d': '2026-10-16',
      '-1d 08:05': '2026-10-13T08:05',
      '+0d 18:00': '2026-10-14T18:00',
      '14:30': '2026-10-14T14:30',
      'thu 16:00': '2026-10-15T16:00',
      'fri 14:30': '2026-10-16T14:30',
      'sat': '2026-10-17',
      'mon': '2026-10-19',
      'wed': '2026-10-21', // gleicher Wochentag = nächste Woche
      'TUE 7:05': '2026-10-20T07:05',
      '2026-12-24 18:00': '2026-12-24T18:00',
      '+18d': '2026-11-01',
    };
    for (final MapEntry(key: spec, value: expected) in table.entries) {
      test('„$spec“ → $expected', () {
        expect(time.resolve(spec).toIso(), expected);
      });
    }

    test('ungültige Angaben', () {
      for (final bad in [
        '',
        'morgen',
        '+1x',
        '25:00',
        '+1d 10:61',
        'x 10:00',
      ]) {
        expect(() => time.resolve(bad), throwsFormatException, reason: bad);
      }
      expect(() => time.resolve('2026-02-30'), throwsFormatException);
    });
  });

  group('parseWallTime / read', () {
    test('ohne Offset = Wandzeit', () {
      expect(
        time.read('2026-10-15T10:00'),
        const WallTime(2026, 10, 15, 10, 0),
      );
      expect(
        time.read('2026-10-15 10:00:30'),
        const WallTime(2026, 10, 15, 10, 0),
      );
      expect(time.read('2026-10-15'), const WallTime(2026, 10, 15));
    });

    test('mit Offset wird in die Zone umgerechnet', () {
      expect(
        time.read('2026-10-15T08:00:00Z'),
        const WallTime(2026, 10, 15, 10, 0),
      );
      expect(
        time.read('2026-10-15T10:00+02:00'),
        const WallTime(2026, 10, 15, 10, 0),
      );
      expect(
        time.read('2026-10-15T04:00-0400'),
        const WallTime(2026, 10, 15, 10, 0),
      );
      // Nach der Zeitumstellung (25.10.) gilt UTC+1.
      expect(
        time.read('2026-10-26T09:00Z'),
        const WallTime(2026, 10, 26, 10, 0),
      );
    });

    test('kein ISO-Wert', () {
      for (final bad in [
        'morgen',
        '2026-13-01',
        '2026-02-30',
        '2026-10-15T24:00',
        '10:00',
      ]) {
        expect(time.read(bad), isNull, reason: bad);
      }
    });
  });

  group('WallTime', () {
    test('Vergleich, Gleichheit, Datum', () {
      const a = WallTime(2026, 10, 15, 10, 0);
      const b = WallTime(2026, 10, 15, 10, 30);
      expect(b.minutesSince(a), 30);
      expect(a.compareTo(b), lessThan(0));
      expect(a.sameDate(b), isTrue);
      expect(a.date, const WallTime(2026, 10, 15));
      expect(a == const WallTime(2026, 10, 15, 10, 0), isTrue);
      expect(a.hashCode, const WallTime(2026, 10, 15, 10, 0).hashCode);
      expect(a.toString(), '2026-10-15T10:00');
      expect(a.date.hasTime, isFalse);
    });
  });

  test('instant zeigt die Wandzeit der Zone', () {
    final i = time.instant;
    expect((i.hour, i.minute, i.day), (9, 0, 14));
    expect(i.toUtc().hour, 7);
    expect(time.timeZone, 'Europe/Berlin');
  });

  test('EvalTime.parse verlangt eine Uhrzeit', () {
    expect(
      () => EvalTime.parse('2026-10-14', 'Europe/Berlin'),
      throwsFormatException,
    );
    expect(
      () => EvalTime.parse('gestern', 'Europe/Berlin'),
      throwsFormatException,
    );
  });
}
