import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  // Language -> distinctive marker word of that language in every sentence.
  const markers = {
    'de': ['entsperre', 'Taschenlampe', 'entsperren', 'geklappt'],
    'en': ['unlock', 'Flashlight', 'unlock', 'did not work'],
    'fr': ['déverrouiller', 'Lampe', 'déverrouiller', 'marche pas'],
  };

  List<String> sentences(String? lang) => [
    LockedTexts.unlock(lang),
    LockedTexts.flashlight(lang, on: true),
    LockedTexts.deferred(lang, navigation: true),
    LockedTexts.failed(lang),
  ];

  for (final e in markers.entries) {
    test('${e.key}: alle Sätze nicht leer und in der Sprache', () {
      final s = sentences(e.key);
      for (var i = 0; i < s.length; i++) {
        expect(s[i], isNotEmpty);
        expect(s[i], contains(e.value[i]), reason: '${e.key} Satz $i');
      }
      expect(LockedTexts.flashlight(e.key, on: false), isNotEmpty);
      expect(
        LockedTexts.flashlight(e.key, on: false),
        isNot(LockedTexts.flashlight(e.key, on: true)),
      );
      final generic = LockedTexts.deferred(e.key, navigation: false);
      expect(generic, isNotEmpty);
      expect(generic, isNot(LockedTexts.deferred(e.key, navigation: true)));
    });
  }

  test('Sprachwahl: Region, Unterstrich, Großschreibung, Fallback', () {
    expect(LockedTexts.unlock('en-US'), 'Please unlock the phone.');
    expect(LockedTexts.unlock('fr_CA'), 'Veuillez déverrouiller le téléphone.');
    expect(LockedTexts.unlock('FR'), 'Veuillez déverrouiller le téléphone.');
    expect(LockedTexts.unlock(null), 'Bitte entsperre das Telefon.');
    expect(LockedTexts.unlock('xx'), 'Bitte entsperre das Telefon.');
    expect(LockedTexts.failed('es-ES'), 'Das hat nicht geklappt.');
  });
}
