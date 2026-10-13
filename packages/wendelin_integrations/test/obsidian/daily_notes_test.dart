import 'package:test/test.dart';
import 'package:wendelin_integrations/src/obsidian/daily_notes.dart';
import 'package:wendelin_integrations/src/obsidian/line_diff.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  // Dienstag, 13. Oktober 2026 (ISO-Woche 42).
  final d = LocalDate(2026, 10, 13);

  group('formatMomentDate', () {
    final cases = <(String, String, String, int)>[
      ('YYYY-MM-DD', 'de', '2026-10-13', 0),
      ('YY/M/D', 'de', '26/10/13', 0),
      ('DD.MM.YYYY', 'de', '13.10.2026', 0),
      ('dddd, Do MMMM YYYY', 'de', 'Dienstag, 13. Oktober 2026', 0),
      (
        'dddd, MMMM Do YYYY',
        'en',
        'Tuesday, October 13th YYYY'.replaceAll('YYYY', '2026'),
        0,
      ),
      ('dddd Do MMMM', 'fr', 'mardi 13 octobre', 0),
      ('ddd MMM', 'de', 'Di. Okt.', 0),
      ('ddd MMM', 'en', 'Tue Oct', 0),
      ('ddd MMM', 'fr', 'mar. oct.', 0),
      ('dd d E', 'de', 'Di 2 2', 0),
      ('GGGG-[W]WW', 'de', '2026-W42', 0),
      ('gggg-ww w W', 'de', '2026-42 42 42', 0),
      ('Q DDD DDDD', 'de', '4 286 286', 0),
      ('YYYY/MM/YYYY-MM-DD', 'de', '2026/10/2026-10-13', 0),
      ('[Tagebuch] YYYY', 'de', 'Tagebuch 2026', 0),
      ('HH:mm H:m', 'de', '09:05 9:5', 9 * 60 + 5),
      ('hh:mm A h a', 'en', '01:30 PM 1 pm', 13 * 60 + 30),
      ('hh A ss s', 'en', '12 AM 00 0', 0),
      ('YYYY', 'xx', '2026', 0),
      ('MMMM', 'xx', 'Oktober', 0),
    ];
    for (final (format, locale, want, minutes) in cases) {
      test('$format ($locale)', () {
        expect(
          formatMomentDate(format, d, locale: locale, minutes: minutes),
          want,
        );
      });
    }

    test('Ordnungszahlen', () {
      String en(int day) =>
          formatMomentDate('Do', LocalDate(2026, 1, day), locale: 'en');
      expect([1, 2, 3, 4, 11, 21, 22, 23, 31].map(en), [
        '1st', '2nd', '3rd', '4th', '11th', '21st', '22nd', '23rd', '31st', //
      ]);
      expect(
        formatMomentDate('Do', LocalDate(2026, 1, 1), locale: 'fr'),
        '1er',
      );
      expect(formatMomentDate('Do', LocalDate(2026, 1, 2), locale: 'fr'), '2');
    });

    test('ISO-Woche am Jahreswechsel', () {
      expect(isoWeek(LocalDate(2027, 1, 1)), (week: 53, year: 2026));
      expect(isoWeek(LocalDate(2024, 12, 30)), (week: 1, year: 2025));
      expect(formatMomentDate('d', LocalDate(2026, 10, 18)), '0');
    });
  });

  group('DailyNoteSettings', () {
    test('Pfad aus Ordner und Format', () {
      expect(const DailyNoteSettings().pathFor(d), '2026-10-13.md');
      expect(
        const DailyNoteSettings(
          folder: 'Journal/',
          format: 'YYYY/MM/DD',
        ).pathFor(d),
        'Journal/2026/10/13.md',
      );
      expect(
        const DailyNoteSettings(format: 'dddd D. MMMM')
            .pathFor(d, locale: 'de'),
        'Dienstag 13. Oktober.md',
      );
    });

    test('Gleichheit', () {
      expect(
        const DailyNoteSettings(folder: 'a', template: 't'),
        const DailyNoteSettings(folder: 'a', template: 't'),
      );
      expect(
        const DailyNoteSettings(folder: 'a').hashCode,
        const DailyNoteSettings(folder: 'a').hashCode,
      );
      expect(
        const DailyNoteSettings(folder: 'a'),
        isNot(const DailyNoteSettings(folder: 'b')),
      );
      expect(
        const ObsidianSettings(vaultName: 'V'),
        const ObsidianSettings(vaultName: 'V'),
      );
      expect(
        const ObsidianSettings(vaultName: 'V').hashCode,
        const ObsidianSettings(vaultName: 'V').hashCode,
      );
    });
  });

  group('fillTemplate', () {
    test('Platzhalter wie in Obsidian', () {
      expect(
        fillTemplate(
          '# {{title}}\n{{date}} {{time}}\n{{ date:dddd }} {{time:HH}}\n'
          '{{DATE:YYYY}} {{unbekannt}} {{date:}}',
          title: '2026-10-13',
          date: d,
          minutes: 8 * 60 + 7,
        ),
        '# 2026-10-13\n2026-10-13 08:07\nDienstag 08\n2026 {{unbekannt}} '
        '2026-10-13',
      );
    });
  });

  group('lineDiff', () {
    test('entfernt, hinzugefügt, Kontext', () {
      expect(lineDiff(['a', 'b', 'c'], ['a', 'x', 'c']), '  a\n- b\n+ x\n  c');
      expect(lineDiff([], ['neu']), '+ neu');
      expect(lineDiff(['alt'], []), '- alt');
      expect(lineDiff(['gleich'], ['gleich']), '  gleich');
    });

    test('lange unveränderte Strecken werden gekürzt', () {
      final before = [for (var i = 0; i < 10; i++) 'z$i'];
      final after = [...before]..[5] = 'neu';
      expect(lineDiff(before, after), '  …\n  z4\n- z5\n+ neu\n  z6\n  …');
    });

    test('höchstens maxLines Zeilen', () {
      final after = [for (var i = 0; i < 50; i++) 'n$i'];
      final out = lineDiff([], after, maxLines: 10).split('\n');
      expect(out, hasLength(11));
      expect(out.last, '… (40 weitere Zeilen)');
    });
  });
}
