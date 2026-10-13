import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/new_topic_command.dart';

void main() {
  group('isNewTopicPhrase', () {
    const phrases = [
      // de
      'neues Thema', 'neues Gespräch', 'neue Unterhaltung', 'vergiss das',
      'fang neu an',
      // fr
      'nouveau sujet', 'nouvelle conversation', 'oublie ça',
      // en
      'new topic', 'new conversation', 'forget that', 'start over',
    ];
    for (final p in phrases) {
      test('„$p“ ist ein Befehl (auch mit Füllwörtern und Satzzeichen)', () {
        expect(isNewTopicPhrase(p), isTrue);
        expect(
          isNewTopicPhrase('${p[0].toUpperCase()}${p.substring(1)}.'),
          isTrue,
        );
        expect(isNewTopicPhrase('okay, $p bitte'), isTrue);
        expect(isNewTopicPhrase('  $p!  '), isTrue);
      });
    }

    test('Füllwörter je Sprache', () {
      expect(isNewTopicPhrase('Bitte neues Thema'), isTrue);
      expect(isNewTopicPhrase('Nouveau sujet, s’il te plaît'), isTrue);
      expect(
        isNewTopicPhrase('Nouvelle conversation s\'il vous plaît'),
        isTrue,
      );
      expect(isNewTopicPhrase('Please start over'), isTrue);
      expect(isNewTopicPhrase('Hey Wendelin, new topic'), isTrue);
    });

    test('längere Sätze und andere Äußerungen sind normale Anfragen', () {
      for (final t in [
        '',
        '   ',
        'okay',
        'bitte',
        'vergiss, dass ich morgen Zahnarzt habe',
        'ein neues Thema bitte',
        'Lass uns über ein neues Thema reden',
        'Fang neu an zu zählen',
        'forget that I like tea',
        'please start over with the list',
        'oublie ça et rappelle-moi demain',
        'neues Thema Urlaub',
      ]) {
        expect(isNewTopicPhrase(t), isFalse, reason: t);
      }
    });
  });
}
