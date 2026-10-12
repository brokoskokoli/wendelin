import 'package:test/test.dart';
import 'package:wendelin_agent/wendelin_agent.dart';

void main() {
  final c = GiveUpClassifier();
  const giveUps = [
    'Das kann ich leider nicht.',
    'Dabei kann ich dir nicht helfen.',
    'Ich bin nicht in der Lage, das zu tun.',
    'Darauf habe ich keinen Zugriff.',
    'Désolé, je ne peux pas vous aider.',
    'Je n’ai pas accès à votre calendrier.',
    'Sorry, I can’t help with that.',
    'I am not able to do this.',
    'Das kann ich nicht.',
    'Ich bin leider nicht in der Lage, dir dabei zu helfen.',
    'Je ne peux pas.',
    "I can't.",
    'That is beyond my   capabilities.',
  ];
  const answers = [
    'Ich kann keinen Termin finden.',
    'Den Termin kann ich leider nicht verschieben, er ist schon vorbei.',
    'Das kann ich nicht finden.',
    "I'm not able to find any events.",
    'Ich bin nicht in der Lage gewesen, den Ort zu finden, er fehlt.',
    'Je ne peux pas trouver ce fichier.',
    "I can't find any events tomorrow.",
    'Erledigt, Tauchen steht morgen um 10 Uhr im Kalender.',
    "Je n'ai trouvé aucun rendez-vous.",
    '',
  ];
  for (final t in giveUps) {
    test('gives up: $t', () => expect(c.isGiveUp(t), isTrue));
  }
  for (final t in answers) {
    test('answers: $t', () => expect(c.isGiveUp(t), isFalse));
  }
  test('custom phrases replace the defaults', () {
    final custom = GiveUpClassifier(patterns: [RegExp('keine ahnung')]);
    expect(custom.isGiveUp('keine   ahnung, sorry'), isTrue);
    expect(custom.isGiveUp('Das kann ich leider nicht.'), isFalse);
  });
}
