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
      'Mach die Taschenlampe an': on,
      'Mach bitte die Taschenlampe aus': off,
      'Schalte die Taschenlampe ein': on,
      'Wendelin, Taschenlampe anschalten': on,
      'Taschenlampe ausmachen': off,
      'Handylampe aus': off,
      'Handy Lampe aus': off,
      // WP114 (T20-Z.5): Weckwort davor, getrennte Komposita
      'Hey Wendelin, Taschenlampe an': on,
      'Wendeln, Taschenlampe an': on,
      'Taschen Lampe an': on,
      'Taschenlampen aus': off,
      // fr
      'Allume la lampe torche': on,
      "Allume la lampe de poche, s'il te plaît": on,
      'Active la lampe torche': on,
      // en
      'flashlight on': on,
      'Flashlight off.': off,
      'Flash light off': off,
      'Eteins la torche': off,
      'Turn on the flashlight': on,
      'Turn the flashlight off': off,
      'Switch off the torch, please': off,
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
      // WP135: room lights are no flashlight (Licht/Lampe/lumière/light/lamp).
      'Licht an',
      'Lampe aus',
      'Schalte das Licht aus',
      'Mach mal das Licht an!',
      'allume la lampe',
      'éteins la lampe',
      'Éteins la lumière',
      'Désactive la lampe',
      'light on',
      'Turn off the lamp',
      'Lampe de',
      'Lampe poche an',
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
      'Licht an aus',
      'Taschenlampe aus an',
      'Hey Wendelin, wie spät ist es',
      'Wendelin Taschenlampe im Keller an',
      'Taschen Lampe',
    ];
    for (final text in negative) {
      test('"$text" -> null', () {
        expect(matchLockedCommand(text), isNull);
      });
    }
  });
}
