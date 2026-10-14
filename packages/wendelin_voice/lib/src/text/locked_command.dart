import 'package:wendelin_core/wendelin_core.dart';

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
/// a flashlight noun („Taschenlampe“, „Licht“, „lampe“, „flashlight“ …)
/// and exactly one direction („an“/„aus“, „allume“/„éteins“, „on“/„off“);
/// politeness and the verb („mach“, „schalte“, „turn“) are allowed,
/// anything else („im Wohnzimmer“, „nicht“, „ist“, a question) gives
/// `null` – the request is then not run while locked. Text is compared
/// folded ([foldForMatch]).
LockedCommand? matchLockedCommand(String text) {
  final words = foldForMatch(text).split(' ').where((w) => w.isNotEmpty);
  var nouns = 0;
  var on = 0;
  var off = 0;
  for (final w in words) {
    if (_nouns.contains(w)) {
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
  'taschenlampe', 'handylampe', 'lampe', 'licht', 'blitzlicht',
  // fr
  'torche', 'lumiere', 'poche',
  // en
  'flashlight', 'flash', 'torch', 'light', 'lamp',
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
