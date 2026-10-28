import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';

/// All built-in integrations (`app/lib/di/integrations/registry.dart`; the
/// app test `topic_words_coverage_test.dart` keeps this list honest).
const _ids = [
  'alarms', 'bring', 'calendar', 'clipboard', 'contacts', 'flashlight', //
  'gtasks', 'ha', 'lists', 'location', 'maps', 'media', 'memory',
  'obsidian',
  'spotify',
  'station',
  'tasks',
  'todoist',
  'waze',
  'weather',
  'web',
];

void main() {
  group('Abdeckung', () {
    for (final MapEntry(:key, :value) in topicWordsByLanguage.entries) {
      test('$key deckt jede Integration ab, alphabetisch', () {
        expect(value.keys.toList(), _ids);
        for (final id in _ids) {
          expect(value[id], isNotEmpty, reason: '$key/$id');
          expect(
            value[id]!.every((w) => foldForMatch(w).isNotEmpty),
            isTrue,
            reason: '$key/$id: leeres Wort',
          );
        }
      });
    }

    test('de, en und fr sind vorhanden', () {
      expect(topicWordsByLanguage.keys, containsAll(['de', 'en', 'fr']));
    });
  });

  group('topicWordsFor', () {
    test('Sprachcode aus BCP-47-Tag, unbekannt → Englisch', () {
      expect(topicWordsFor('de-DE'), same(topicWordsByLanguage['de']));
      expect(topicWordsFor('fr_CH'), same(topicWordsByLanguage['fr']));
      expect(topicWordsFor('xx'), same(topicWordsByLanguage['en']));
      expect(topicWordsFor(null), same(topicWordsByLanguage['en']));
    });
  });

  group('topicIntegrationsIn', () {
    final cases = <(String, String, String?)>[
      ('Stell mir einen Wecker um 7', 'de', 'alarms'),
      ('Ich will früh aufstehen', 'de', 'alarms'),
      ('Réveille-moi à sept heures', 'fr', 'alarms'),
      ('Wake me up at seven', 'en', 'alarms'),
      ('Wie wird das Wetter morgen?', 'de', 'weather'),
      ('Quelle météo demain ?', 'fr', 'weather'),
      ('Navigate to the station', 'en', 'maps'),
      ('Schreib das in meine Notizen', 'de', 'obsidian'),
      ('Ruf mich bitte an', 'de', 'contacts'),
      ('Send a text message to Anna', 'en', 'contacts'),
      ('Turn the fan on', 'en', 'ha'),
      ('Fan on in the bedroom', 'en', 'ha'),
      ('Schick Anna eine Nachricht', 'de', 'contacts'),
    ];
    for (final (text, lang, id) in cases) {
      test('„$text“ ($lang) → $id', () {
        expect(topicIntegrationsIn(text, languageTag: lang), contains(id));
      });
    }

    test('nur die aktuelle Sprache', () {
      expect(topicIntegrationsIn('Wecker', languageTag: 'fr'), isEmpty);
    });

    test('kein Treffer ohne Themenwort', () {
      expect(
        topicIntegrationsIn('Erzähl mir einen Witz', languageTag: 'de'),
        isEmpty,
      );
      expect(topicIntegrationsIn('', languageTag: 'de'), isEmpty);
    });

    test('zu allgemeine Stämme treffen nicht', () {
      const neg = <(String, String, String)>[
        ('That was fantastic', 'en', 'ha'),
        ('Eventually it worked', 'en', 'calendar'),
        ('Listen to this story', 'en', 'lists'),
        ('The text is long', 'en', 'contacts'),
        ('A duet of two singers', 'en', 'gtasks'),
        ('Gibt es Nachrichten?', 'de', 'contacts'),
        ('Die Rufbereitschaft', 'de', 'contacts'),
        ('Wir müssen uns treffen', 'de', 'calendar'),
      ];
      for (final (text, lang, id) in neg) {
        expect(
          topicIntegrationsIn(text, languageTag: lang),
          isNot(contains(id)),
          reason: text,
        );
      }
      expect(
        topicIntegrationsIn('Gibt es Nachrichten?', languageTag: 'de'),
        contains('web'),
      );
    });

    test('Wortanfang, nicht Wortmitte', () {
      expect(
        topicIntegrationsIn('Eine Ruine', languageTag: 'de'),
        isNot(contains('alarms')),
      );
      expect(topicIntegrationsIn('Das Handtuch', languageTag: 'de'), isEmpty);
    });
  });
}
