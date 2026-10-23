import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

const _domains = {'light', 'cover', 'switch', 'climate'};

void main() {
  group('Abdeckung', () {
    test('de, en und fr sind vorhanden', () {
      expect(haWordsByLanguage.keys, containsAll(['de', 'en', 'fr']));
      expect(haTopicExtraByLanguage.keys, haWordsByLanguage.keys);
    });

    for (final MapEntry(:key, :value) in haWordsByLanguage.entries) {
      test('$key deckt jeden Gerätetyp und jede Aktion ab', () {
        expect(value.types.keys.toSet(), _domains);
        for (final d in _domains) {
          expect(value.types[d], isNotEmpty, reason: '$key/$d');
        }
        for (final a in HaAction.values) {
          expect(value.actions[a], isNotEmpty, reason: '$key/$a');
        }
        expect(value.percent, isNotEmpty);
        expect(value.blockers, isNotEmpty, reason: '$key blockers');
        expect(value.degrees, isNotEmpty);
        expect(value.fillers, isNotEmpty);
        expect(value.recognitionErrors['cover'], isNotEmpty);
        final all = [
          for (final l in value.types.values) ...l,
          for (final l in value.recognitionErrors.values) ...l,
          for (final l in value.actions.values) ...l,
          ...value.percent,
          ...value.degrees,
        ];
        expect(all.where((w) => foldForMatch(w).isEmpty), isEmpty);
      });

      test('$key: Gerätetypen stehen in den Themenwörtern von ha', () {
        final topic = topicWordsByLanguage[key]!['ha']!;
        for (final stems in value.types.values) {
          expect(topic, containsAll(stems), reason: key);
        }
        expect(topic, containsAll(haTopicExtraByLanguage[key]!));
      });
    }
  });

  // Je Sprache und Aktion mindestens ein echter Satz.
  const phrases = <String, Map<HaAction, List<String>>>{
    'de': {
      HaAction.on: ['Mach das Licht an', 'Lampe ein', 'Schalte die Lampe ein'],
      HaAction.off: ['Licht aus', 'Mach die Lampe aus', 'Schalt das Licht ab'],
      HaAction.open: ['Rollo rauf', 'Rollo hoch', 'Mach das Rollo auf'],
      HaAction.close: ['Rollo runter', 'Rollo zu', 'Lass das Rollo runter'],
      HaAction.stop: ['Rollo stopp', 'Halt das Rollo an', 'Rollo halt'],
      HaAction.brighter: ['Licht heller', 'Mach es heller'],
      HaAction.dimmer: ['Licht dunkler', 'Dimm das Licht'],
      HaAction.half: ['Rollo halb', 'Rollo halbe Höhe'],
    },
    'en': {
      HaAction.on: ['Turn on the light', 'Lamp on'],
      HaAction.off: ['Turn off the light', 'Lamp off'],
      HaAction.open: ['Open the blinds', 'Blinds up', 'Raise the blinds'],
      HaAction.close: ['Close the blinds', 'Blinds down', 'Lower the shade'],
      HaAction.stop: ['Stop the blinds', 'Halt'],
      HaAction.brighter: ['Make the light brighter'],
      HaAction.dimmer: ['Dim the light', 'Make it darker'],
      HaAction.half: ['Blinds halfway', 'Blinds half'],
    },
    'fr': {
      HaAction.on: ['Allume la lumière', 'Mets la lampe'],
      HaAction.off: ['Éteins la lumière', 'Coupe la lampe'],
      HaAction.open: ['Ouvre le volet', 'Monte le volet', 'Lève le store'],
      HaAction.close: [
        'Ferme le volet',
        'Descends le store',
        'Baisse le volet',
      ],
      HaAction.stop: ['Arrête le volet', 'Stop le volet'],
      HaAction.brighter: ['Plus lumineux', 'Éclaircis la lumière'],
      HaAction.dimmer: ['Plus sombre', 'Tamise la lumière'],
      HaAction.half: ['Volet à moitié'],
    },
  };

  group('haActionsIn', () {
    for (final MapEntry(key: lang, value: byAction) in phrases.entries) {
      for (final a in HaAction.values) {
        test('$lang: Beispiele für $a', () {
          expect(byAction[a], isNotEmpty, reason: '$lang/$a ohne Beispiel');
          for (final text in byAction[a]!) {
            expect(
              haActionsIn(text, languageTag: lang),
              contains(a),
              reason: text,
            );
          }
        });
      }
    }

    test('kurze Wörter treffen nur als ganze Wörter', () {
      expect(
        haActionsIn('Der Anhalter kauft Zucker', languageTag: 'de'),
        isEmpty,
      );
      expect(haActionsIn('Zucker einkaufen', languageTag: 'de'), isEmpty);
      expect(haActionsIn('Optional upgrade', languageTag: 'en'), isEmpty);
    });

    test('mehrere Aktionen bleiben mehrere (mehrdeutig)', () {
      expect(haActionsIn('Licht an und Rollo runter', languageTag: 'de'), {
        HaAction.on,
        HaAction.close,
      });
    });

    test('Sprachcode aus Tag, unbekannt → Englisch', () {
      expect(haActionsIn('Rollo runter', languageTag: 'de-DE'), {
        HaAction.close,
      });
      expect(haWordsFor('xx'), same(haWordsByLanguage['en']));
      expect(haWordsFor(null), same(haWordsByLanguage['en']));
    });
  });

  group('haDomainsIn', () {
    const types = <(String, String, String)>[
      ('Lampe Wohnzimmer', 'light', 'de'),
      ('Leuchte im Flur', 'light', 'de'),
      ('Stehlampe', 'light', 'de'),
      ('Rollo Wohnzimmer', 'cover', 'de'),
      ('Rollläden im Büro', 'cover', 'de'),
      ('Jalousie', 'cover', 'de'),
      ('Markise', 'cover', 'de'),
      ('Steckdose Küche', 'switch', 'de'),
      ('Heizung Bad', 'climate', 'de'),
      ('Thermostat', 'climate', 'de'),
      ('Rolle Wohnzimmer', 'cover', 'de'), // Erkennungsfehler
      ('Living room lamp', 'light', 'en'),
      ('Bedroom blinds', 'cover', 'en'),
      ('Kitchen plug', 'switch', 'en'),
      ('Radiator', 'climate', 'en'),
      ('Lumière du salon', 'light', 'fr'),
      ('Volet roulant', 'cover', 'fr'),
      ('Prise cuisine', 'switch', 'fr'),
      ('Chauffage', 'climate', 'fr'),
    ];
    for (final (text, domain, lang) in types) {
      test('„$text“ ($lang) → $domain', () {
        expect(haDomainsIn(text, languageTag: lang), {domain});
        expect(haDomainsIn(text), contains(domain), reason: 'alle Sprachen');
      });
    }

    test('ohne Typwort nichts', () {
      expect(haDomainsIn('Wohnzimmer Nord'), isEmpty);
      expect(haDomainsIn(''), isEmpty);
    });

    test('Typwörter fallen aus dem Namensteil', () {
      expect(haWithoutTypeWords('Lampe Wohnzimmer'), 'wohnzimmer');
      expect(haWithoutTypeWords('Rolle im Wohnzimmer'), 'wohnzimmer');
      expect(haWithoutTypeWords('die Lampe'), isEmpty);
    });
  });

  group('Themenwörter', () {
    test('Verhörer lösen ha nur mit Aktion aus', () {
      expect(
        topicIntegrationsIn('Rolle runter im Wohnzimmer', languageTag: 'de'),
        contains('ha'),
      );
      expect(
        topicIntegrationsIn('Das war meine Rolle im Film', languageTag: 'de'),
        isNot(contains('ha')),
      );
    });
    test('neue Typwörter schalten ha frei', () {
      expect(
        topicIntegrationsIn('Markise ausfahren', languageTag: 'de'),
        contains('ha'),
      );
      expect(
        topicIntegrationsIn('Ferme le volet roulant', languageTag: 'fr'),
        contains('ha'),
      );
    });
  });

  group('haHasBlocker', () {
    test('Ausnahme nur für ganzes Wort: Saunatür bleibt gesperrt', () {
      expect(haHasBlocker('Saunatür switch.saunatur'), isTrue);
      expect(haHasBlocker('Sauna switch.saunatur'), isTrue);
      expect(haHasBlocker('Saunatür'), isTrue);
    });

    test('Ausnahme nimmt keinen Stamm mit: Motortor (de)', () {
      expect(haHasBlocker('Motortor switch.motortor'), isTrue);
    });

    test('en: Navigate nur als Teil eines Worts bleibt gesperrt', () {
      expect(haHasBlocker('Navigates switch.x'), isTrue);
      expect(haHasBlocker('Gps navigategate'), isTrue);
      expect(haHasBlocker('Navigate switch.x'), isFalse);
    });

    test('fr: Teil eines Worts mit porte bleibt gesperrt', () {
      expect(haHasBlocker('Support switch.x'), isFalse);
      expect(haHasBlocker('Supporte switch.x'), isFalse);
      expect(haHasBlocker('Supporteur switch.x'), isTrue);
      expect(haHasBlocker('Soupporte switch.x'), isTrue);
    });

    test('ganze Ausnahmewörter bleiben erlaubt', () {
      for (final n in ['Ventilator', 'Monitor', 'Temperatur', 'Radiator']) {
        expect(haHasBlocker('$n switch.ok'), isFalse, reason: n);
      }
      expect(haHasBlocker('Ventilator switch.ventilator'), isFalse);
      expect(haHasBlocker('Wohnzimmer-Monitor switch.wohn_monitor'), isFalse);
    });

    test('Raumtemperatur ist gesperrt (gewollt, fail-closed)', () {
      expect(haHasBlocker('Raumtemperatur switch.x'), isTrue);
      expect(haHasBlocker('Temperaturtür switch.x'), isTrue);
    });
  });
}
