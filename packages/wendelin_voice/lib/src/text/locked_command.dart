import 'package:wendelin_core/wendelin_core.dart';

import '../wake/wake_verifier.dart' show stripWakeWord;

/// What may run while the device is locked (K16): the flashlight only.
enum LockedCommand {
  /// Flashlight on.
  flashlightOn,

  /// Flashlight off.
  flashlightOff,
}

/// Recognizes a flashlight command in a spoken [text] (de/fr/en) without
/// any model, so it can run on a locked device (WP53, K16).
///
/// Conservative on purpose: every word must be known. The utterance needs
/// a flashlight noun („Taschenlampe“, „lampe de poche“, „flashlight“ …;
/// „Licht“/„Lampe“ alone are room lights, WP135)
/// and exactly one direction („an“/„aus“, „allume“/„éteins“, „on“/„off“);
/// politeness and the verb („mach“, „schalte“, „turn“) are allowed,
/// anything else („im Wohnzimmer“, „nicht“, „ist“, a question) gives
/// `null` – the request is then not run while locked. Text is compared
/// folded ([foldForMatch]).
LockedCommand? matchLockedCommand(String text) {
  // A leading wake word (also misheard: „Wendeln“, „Hey Wendelin“) is no
  // unknown word (WP114, T20-Z.5).
  final words = foldForMatch(stripWakeWord(text))
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  var nouns = 0;
  var on = 0;
  var off = 0;
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (i + 1 < words.length && _nouns.contains(w + words[i + 1])) {
      // Speech recognition splits compounds: „Taschen Lampe“ (WP114).
      nouns++;
      i++;
    } else if (w == 'lampe' &&
        i + 1 < words.length &&
        words[i + 1] == 'torche') {
      // „lampe torche“ (WP135).
      nouns++;
      i++;
    } else if (w == 'lampe' &&
        i + 2 < words.length &&
        words[i + 1] == 'de' &&
        words[i + 2] == 'poche') {
      // „lampe de poche“: „lampe“ alone is a room light (WP135).
      nouns++;
      i += 2;
    } else if (_nouns.contains(w)) {
      nouns++;
    } else if (_on.contains(w)) {
      on++;
    } else if (_off.contains(w)) {
      off++;
    } else if (!_neutral.contains(w)) {
      return null;
    }
  }
  if (nouns == 0 || (on > 0) == (off > 0)) return null;
  return on > 0 ? LockedCommand.flashlightOn : LockedCommand.flashlightOff;
}

const _nouns = {
  // de
  'taschenlampe', 'taschenlampen', 'handylampe', 'blitzlicht',
  // fr
  'torche', 'poche',
  // en
  'flashlight', 'flash', 'torch',
};

const _on = {
  // de
  'an', 'ein', 'anschalten', 'einschalten', 'anmachen', 'einmachen',
  'aktivieren',
  // fr
  'allume', 'allumer', 'active', 'activer', 'mets', 'mettre',
  // en
  'on',
};

const _off = {
  // de
  'aus', 'ausschalten', 'ausmachen', 'abschalten', 'deaktivieren',
  // fr
  'eteins', 'eteindre', 'desactive', 'desactiver', 'coupe', 'couper',
  // en
  'off',
};

const _neutral = {
  // de: verbs, articles, politeness
  'mach', 'mache', 'schalte', 'schalt', 'die', 'das', 'der', 'mal', 'bitte',
  'wendelin', 'hey', 'okay', 'ok', 'jetzt', 'doch', 'schalten', 'meine',
  'handy',
  // fr
  'la', 'le', 'l', 'ma', 'de', 'stp', 'svp', 's', 'il', 'te', 'plait',
  'vous',
  // en
  'turn', 'switch', 'put', 'the', 'please', 'my', 'now', 'phone',
};
