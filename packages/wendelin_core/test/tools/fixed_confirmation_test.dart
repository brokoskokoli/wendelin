import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

String? r(String key, String? lang, [Map<String, Object> params = const {}]) =>
    renderConfirmation(ConfirmationSentence(key, params), lang);

void main() {
  group('Vorlagen', () {
    test('alle Sprachen haben dieselben Schlüssel', () {
      expect(confirmationLanguages.keys, containsAll(['de', 'en', 'fr']));
      final de = confirmationLanguages['de']!.templates.keys.toSet();
      for (final MapEntry(:key, :value) in confirmationLanguages.entries) {
        expect(value.templates.keys.toSet(), de, reason: key);
      }
    });

    test('jede Vorlage hat dieselben Platzhalter in jeder Sprache', () {
      Set<String> holes(String t) => {
        for (final m in RegExp(r'\{(\w+)\}').allMatches(t)) m[1]!,
      };
      final de = confirmationLanguages['de']!.templates;
      for (final MapEntry(:key, :value) in confirmationLanguages.entries) {
        for (final e in de.entries) {
          expect(
            holes(value.templates[e.key]!),
            holes(e.value),
            reason: '$key ${e.key}',
          );
        }
      }
    });

    test('jede Einzahl-Variante hat eine Grundvorlage', () {
      for (final lang in confirmationLanguages.values) {
        for (final k in lang.templates.keys.where((k) => k.endsWith('#one'))) {
          expect(
            lang.templates,
            contains(k.substring(0, k.length - 4)),
            reason: k,
          );
        }
      }
    });
  });

  group('renderConfirmation', () {
    test('Sprache aus Tag, null = de', () {
      expect(r('flashlight.on', null), 'Die Taschenlampe ist an.');
      expect(r('flashlight.on', 'de-DE'), 'Die Taschenlampe ist an.');
      expect(r('flashlight.on', 'EN_us'), 'The flashlight is on.');
      expect(r('flashlight.on', 'fr'), 'La lampe de poche est allumée.');
    });

    test('unbekannte Sprache, Vorlage oder fehlender Parameter: null', () {
      expect(r('flashlight.on', 'es'), isNull);
      expect(r('gibt.es.nicht', 'de'), isNull);
      expect(r('list.added', 'de', {'list': 'Einkauf'}), isNull);
    });

    test('count 1 wählt die Einzahl', () {
      const p = {
        'items': ['Milch'],
        'list': 'Einkauf',
      };
      expect(
        r('list.added', 'de', {...p, 'count': 1}),
        contains('steht jetzt'),
      );
      expect(
        r('list.added', 'de', {...p, 'count': 2}),
        contains('stehen jetzt'),
      );
      expect(r('list.added', 'de', p), contains('stehen jetzt'));
    });

    test('joinConfirmations hängt Sätze aneinander', () {
      expect(joinConfirmations(['A.', 'B.']), 'A. B.');
    });
  });

  group('Formate', () {
    final de = confirmationLanguages['de']!;
    final en = confirmationLanguages['en']!;
    final fr = confirmationLanguages['fr']!;

    test('Aufzählung', () {
      expect(de.joinList([]), '');
      expect(de.joinList(['A']), 'A');
      expect(de.joinList(['A', 'B']), 'A und B');
      expect(de.joinList(['A', 'B', 'C']), 'A, B und C');
      expect(en.joinList(['A', 'B', 'C']), 'A, B and C');
      expect(fr.joinList(['A', 'B', 'C']), 'A, B et C');
    });

    test('Dauer', () {
      expect(de.duration(const Duration(minutes: 10)), '10 Minuten');
      expect(
        de.duration(const Duration(hours: 1, minutes: 1)),
        '1 Stunde und 1 Minute',
      );
      expect(de.duration(Duration.zero), '0 Sekunden');
      expect(
        en.duration(const Duration(minutes: 1, seconds: 30)),
        contains('30'),
      );
      expect(fr.duration(const Duration(minutes: 5)), contains('5'));
    });

    test('Wochentage', () {
      expect(de.days({}), 'einmalig');
      expect(de.days({1, 2, 3, 4, 5}), 'montags bis freitags');
      expect(de.days({1, 2, 3, 4, 5, 6, 7}), 'täglich');
      expect(de.days({3, 1}), 'montags und mittwochs');
    });

    test('Termin', () {
      expect(
        de.dateTime(DateTime(2026, 10, 20, 9, 5)),
        'Di. 20.10., 09:05 Uhr',
      );
      expect(en.dateTime(DateTime(2026, 10, 20, 9, 5)), contains('09:05'));
      expect(fr.dateTime(DateTime(2026, 10, 20, 9, 5)), contains('09:05'));
    });
  });

  test('ToolOutcome.text reicht fixed durch', () {
    const s = ConfirmationSentence('flashlight.on');
    expect(ToolOutcome.text('ok', fixed: s).fixed, same(s));
    expect(ToolOutcome.text('ok').fixed, isNull);
  });
}
