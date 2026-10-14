import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  const on = LockedCommand.flashlightOn;
  const off = LockedCommand.flashlightOff;

  group('flashlight commands (de/fr/en)', () {
    final positive = <String, LockedCommand>{
      // de
      'Taschenlampe an': on,
      'Taschenlampe an.': on,
      'Taschenlampe ein': on,
      'Taschenlampe aus': off,
      'Licht an': on,
      'Lampe aus': off,
      'Mach die Taschenlampe an': on,
      'Mach bitte die Taschenlampe aus': off,
      'Schalte die Taschenlampe ein': on,
      'Schalte das Licht aus': off,
      'Wendelin, Taschenlampe anschalten': on,
      'Taschenlampe ausmachen': off,
      'Mach mal das Licht an!': on,
      'Handylampe aus': off,
      // fr
      'allume la lampe': on,
      'Allume la lampe torche': on,
      "Allume la lampe de poche, s'il te plaît": on,
      'éteins la lampe': off,
      'Éteins la lumière': off,
      'Active la lampe torche': on,
      'Désactive la lampe': off,
      // en
      'flashlight on': on,
      'Flashlight off.': off,
      'Turn on the flashlight': on,
      'Turn the flashlight off': off,
      'Switch off the torch, please': off,
      'light on': on,
      'Turn off my flashlight': off,
    };
    positive.forEach((text, expected) {
      test('"$text" -> $expected', () {
        expect(matchLockedCommand(text), expected);
      });
    });
  });

  group('nothing else runs while locked', () {
    const negative = [
      '',
      'Taschenlampe',
      'Licht',
      'an',
      'Taschenlampe an und aus',
      'Wie spät ist es',
      'Wie viel Uhr ist es?',
      'Was steht morgen im Kalender?',
      'Lies meine Nachrichten vor',
      'Mach das Licht im Wohnzimmer an',
      'Taschenlampe nicht an',
      'Ist die Taschenlampe an?',
      'Schalte die Taschenlampe an und lies meine Mails',
      'Ruf Anna an',
      'Schalte den Wecker aus',
      'Mach das Radio an',
      'Quelle heure est-il',
      'Allume la télé',
      'Éteins le chauffage',
      "What's the weather",
      'Turn on the bedroom light',
      'Send a message to Anna',
      'Neues Thema',
      'Licht an Anna schreiben',
    ];
    for (final text in negative) {
      test('"$text" -> null', () {
        expect(matchLockedCommand(text), isNull);
      });
    }
  });
}
